#!/usr/bin/env bash
# validate-artifacts.sh
# Validates that a built artifact is a plausible mod jar for the selected loader.
#
# This script intentionally stays simple and fail-fast:
# - Uses canonical gradle.properties via quick-detect.sh
# - Resolves artifact path via compute-artifact-path.sh unless explicitly provided
# - Ensures the jar is a valid zip and contains loader-specific metadata files

set -euo pipefail

usage() {
  cat <<'EOF'
Usage: validate-artifacts.sh --project-root <path> [--loader <forge|neoforge|fabric>] [--artifact-path <path>]

Options:
  --project-root <path>       Project root containing gradle.properties
  --loader <type>             Required for multi-loader projects; must match project when single-loader
  --artifact-path <path>      Artifact path relative to project-root; auto-computed if omitted
  -h, --help                  Show this help

Outputs (key=value):
  loader_type
  minecraft_version
  artifact_path
  validation_status (pass)
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

# Determine canonical properties and loader context.
detect_out="$(bash "${SCRIPT_DIR}/quick-detect.sh" --project-root "${project_root}")"

minecraft_version="$(echo "$detect_out" | sed -n 's/^minecraft_version=//p' | head -n 1)"
loader_multi="$(echo "$detect_out" | sed -n 's/^loader_multi=//p' | head -n 1)"
loader_type="$(echo "$detect_out" | sed -n 's/^loader_type=//p' | head -n 1)"
active_loaders="$(echo "$detect_out" | sed -n 's/^active_loaders=//p' | head -n 1)"

[[ -n "$minecraft_version" ]] || fail "failed to read minecraft_version from quick-detect output"

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
if [[ ! -f "$artifact_abs" ]]; then
  echo "ERROR: artifact does not exist: ${artifact_path}" >&2
  echo "INFO: expected absolute path: ${artifact_abs}" >&2
  echo "INFO: listing ${project_root%/}/build/libs (if present):" >&2
  ls -la "${project_root%/}/build/libs" 2>/dev/null || true
  echo "INFO: searching for jars under ${project_root%/}/build (maxdepth 6):" >&2
  find "${project_root%/}/build" -maxdepth 6 -type f -name '*.jar' -print 2>/dev/null || true
  echo "INFO: artifact naming must match the enforced contract computed from gradle.properties." >&2
  echo "INFO: if the jar exists but under a different name/location, adjust your build output to match (or pass --artifact-path where supported)." >&2
  exit 1
fi
[[ -s "$artifact_abs" ]] || fail "artifact is empty: ${artifact_path}"

# Validate the jar is a zip.
require_cmd unzip
unzip -tq "$artifact_abs" >/dev/null

# Validate required metadata presence.
# Note: We avoid deep parsing (toml/json) here; presence checks are fail-fast and portable.
require_file=""
case "$loader_type" in
  forge)
    require_file="META-INF/mods.toml"
    ;;
  neoforge)
    require_file="META-INF/neoforge.mods.toml"
    ;;
  fabric)
    require_file="fabric.mod.json"
    ;;
esac

contents="$(unzip -Z1 "$artifact_abs" 2>/dev/null || true)"
[[ -n "$contents" ]] || fail "failed to list jar contents: ${artifact_path}"

echo "$contents" | grep -Fxq "META-INF/MANIFEST.MF" || fail "missing META-INF/MANIFEST.MF in ${artifact_path}"
echo "$contents" | grep -Fxq "$require_file" || fail "missing ${require_file} in ${artifact_path}"

{
  echo "loader_type=${loader_type}"
  echo "minecraft_version=${minecraft_version}"
  echo "artifact_path=${artifact_path}"
  echo "validation_status=pass"
}
