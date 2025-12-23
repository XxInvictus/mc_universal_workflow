#!/usr/bin/env bash
# validate-mappings.sh
# Heuristically detects mapping type of the built artifact and enforces
# loader expectations:
# - Forge: SRG or Mojmap (Forge toolchains vary)
# - NeoForge: Mojmap
# - Fabric: Intermediary
#
# This is a "v2 subset" implementation: fast, fail-fast, and dependency-light.
# It uses string pattern heuristics over jar contents (not full bytecode analysis).

set -euo pipefail

usage() {
  cat <<'EOF'
Usage: validate-mappings.sh --project-root <path> [--loader <forge|neoforge|fabric>] [--artifact-path <path>]

Options:
  --project-root <path>       Project root containing gradle.properties
  --loader <type>             Required for multi-loader projects; must match project when single-loader
  --artifact-path <path>      Artifact path relative to project-root; auto-computed if omitted
  -h, --help                  Show this help

Outputs (key=value):
  loader_type
  artifact_path
  mapping_type (srg|mojmap|intermediary|mixed|unknown)
  expected_mapping (single value or 'a|b')
  validation_status (pass|fail)
EOF
}

fail() {
  local message="$1"
  echo "ERROR: ${message}" >&2
  exit 1
}

require_cmd() {
  local cmd="$1"
  command -v "$cmd" >/dev/null 2>&1 || fail "required command not found: ${cmd}"
}

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

project_root=""
loader=""
artifact_path=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --project-root)
      project_root="${2:-}"
      [[ -n "$project_root" ]] || fail "--project-root requires a value"
      shift 2
      ;;
    --loader)
      loader="${2:-}"
      [[ -n "$loader" ]] || fail "--loader requires a value"
      shift 2
      ;;
    --artifact-path)
      artifact_path="${2:-}"
      [[ -n "$artifact_path" ]] || fail "--artifact-path requires a value"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      fail "Unknown argument: $1"
      ;;
  esac
done

[[ -n "$project_root" ]] || fail "--project-root is required"
[[ -d "$project_root" ]] || fail "project root does not exist: ${project_root}"

require_cmd unzip
require_cmd strings

# Determine loader context.
detect_out="$(bash "${SCRIPT_DIR}/quick-detect.sh" --project-root "${project_root}")"
loader_multi="$(echo "$detect_out" | sed -n 's/^loader_multi=//p' | head -n 1)"
loader_type="$(echo "$detect_out" | sed -n 's/^loader_type=//p' | head -n 1)"
active_loaders="$(echo "$detect_out" | sed -n 's/^active_loaders=//p' | head -n 1)"

if [[ "$loader_multi" == "true" ]]; then
  [[ -n "$loader" ]] || fail "multi-loader project requires --loader (active_loaders=${active_loaders})"
  loader_type="$loader"
else
  if [[ -n "$loader" && "$loader" != "$loader_type" ]]; then
    fail "--loader was provided but project is single-loader (${loader_type})"
  fi
fi

case "$loader_type" in
  forge|neoforge|fabric) ;;
  *) fail "unsupported loader_type=${loader_type}" ;;
esac

# Resolve artifact path.
if [[ -z "$artifact_path" ]]; then
  compute_args=("--project-root" "$project_root")
  if [[ "$loader_multi" == "true" ]]; then
    compute_args+=("--loader" "$loader_type")
  fi
  artifact_path="$(bash "${SCRIPT_DIR}/compute-artifact-path.sh" "${compute_args[@]}" | sed -n 's/^artifact_path=//p' | head -n 1)"
fi

[[ -n "$artifact_path" ]] || fail "failed to resolve artifact_path"

artifact_abs="${project_root%/}/${artifact_path}"
[[ -f "$artifact_abs" ]] || fail "artifact does not exist: ${artifact_path}"
[[ -s "$artifact_abs" ]] || fail "artifact is empty: ${artifact_path}"

# Generate a bounded strings sample from the jar.
# IMPORTANT: the jar is a zip; scanning the compressed container bytes is unreliable.
# Instead, extract to a temp dir and run strings over extracted files.
tmp_dir="$(mktemp -d)"
cleanup() {
  rm -rf "$tmp_dir"
}
trap cleanup EXIT

if ! unzip -q "$artifact_abs" -d "$tmp_dir" >/dev/null 2>&1; then
  fail "failed to unzip artifact for mapping scan: ${artifact_path}"
fi

# Prefer scanning .class files; include any plain-text markers too.
strings_sample="$((
  find "$tmp_dir" -type f \( -name '*.class' -o -name '*.txt' -o -name '*.json' -o -name '*.toml' \) -print0 \
  | while IFS= read -r -d '' f; do
      strings -a "$f" 2>/dev/null || true
    done \
  | head -n 200000
) || true)"

if [[ -z "$strings_sample" ]]; then
  fail "failed to read strings from extracted artifact (strings returned empty): ${artifact_path}"
fi

count_re() {
  local pattern="$1"
  # Under `set -euo pipefail`, grep exits 1 when there are no matches, which would
  # incorrectly terminate the script. Temporarily disable pipefail for this count.
  set +o pipefail
  local count
  count="$(echo "$strings_sample" | grep -Eo "$pattern" 2>/dev/null | wc -l | tr -d ' ')"
  set -o pipefail
  echo "$count"
}

# Heuristics
# - Intermediary: class_#### / method_#### patterns are common
# - SRG: func_####_a / field_####_a patterns are common
# - Mojmap: readable net/minecraft paths and low intermediary/srg signals
intermediary_class_count="$(count_re 'class_[0-9]{1,6}')"
intermediary_method_count="$(count_re 'method_[0-9]{1,6}')"
intermediary_score=$((intermediary_class_count + intermediary_method_count))

srg_func_count="$(count_re 'func_[0-9]{1,6}_[a-zA-Z]')"
srg_field_count="$(count_re 'field_[0-9]{1,6}_[a-zA-Z]')"
srg_score=$((srg_func_count + srg_field_count))

mojmap_path_count="$(count_re 'net/minecraft/(world|client|server|core|resources)/')"
mojmap_score=$((mojmap_path_count))

mapping_type="unknown"

# Basic classification thresholds.
# These are intentionally conservative: we only claim a mapping type when
# the characteristic patterns are clearly present.
intermediary_hit=false
srg_hit=false
mojmap_hit=false

if [[ "$intermediary_score" -ge 25 ]]; then
  intermediary_hit=true
fi

if [[ "$srg_score" -ge 25 ]]; then
  srg_hit=true
fi

if [[ "$mojmap_score" -ge 10 ]]; then
  mojmap_hit=true
fi

hit_count=0
$intermediary_hit && hit_count=$((hit_count + 1))
$srg_hit && hit_count=$((hit_count + 1))
$mojmap_hit && hit_count=$((hit_count + 1))

if [[ "$hit_count" -ge 2 ]]; then
  mapping_type="mixed"
elif $intermediary_hit; then
  mapping_type="intermediary"
elif $srg_hit; then
  mapping_type="srg"
elif $mojmap_hit; then
  mapping_type="mojmap"
else
  mapping_type="unknown"
fi

expected_mapping=""
expected_mapping_regex=""
case "$loader_type" in
  forge)
    expected_mapping="srg|mojmap"
    expected_mapping_regex='^(srg|mojmap)$'
    ;;
  neoforge)
    expected_mapping="mojmap"
    expected_mapping_regex='^mojmap$'
    ;;
  fabric)
    expected_mapping="intermediary"
    expected_mapping_regex='^intermediary$'
    ;;
esac

validation_status="pass"
if ! [[ "$mapping_type" =~ $expected_mapping_regex ]]; then
  validation_status="fail"
fi

{
  echo "loader_type=${loader_type}"
  echo "artifact_path=${artifact_path}"
  echo "mapping_type=${mapping_type}"
  echo "expected_mapping=${expected_mapping}"
  echo "validation_status=${validation_status}"
}

if [[ "$validation_status" != "pass" ]]; then
  fail "mapping validation failed: expected ${expected_mapping} for ${loader_type}, got ${mapping_type}"
fi
