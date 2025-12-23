#!/usr/bin/env bash
# health-check.sh
# One-stop wrapper to validate a consumer repo against this workflow's strict contract.

set -euo pipefail

readonly SCRIPT_NAME="$(basename "$0")"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

usage() {
  cat <<'EOF'
Usage: health-check.sh [OPTIONS]

Options:
  --project-root <path>         Project root containing gradle.properties (default: .)
  --loader <forge|neoforge|fabric>
                                Restrict checks to one loader (useful for multi-loader)
  --validate-properties <bool>  Run validate-gradle-properties.sh (default: true)
  --validate-deps <bool>        Run validate-dependencies-yml.sh (default: true)
  --validate-artifacts <bool>   Run validate-artifacts.sh (default: true)
  --validate-mappings <bool>    Run validate-mappings.sh (default: true)
  -h, --help                    Show this help

Notes:
  - Artifact/mapping validation expects the mod jar(s) to already exist at the enforced paths.
EOF
}

fail() {
  local message="$1"
  echo "ERROR: ${message}" >&2
  exit 1
}

trim() {
  local s="$1"
  s="${s#${s%%[![:space:]]*}}"
  s="${s%${s##*[![:space:]]}}"
  printf '%s' "$s"
}

require_bool() {
  local name="$1"
  local value="$2"
  case "$value" in
    true|false) ;;
    *) fail "${name} must be true|false (got '${value}')" ;;
  esac
}

project_root="."
loader=""
validate_properties="true"
validate_deps="true"
validate_artifacts="true"
validate_mappings="true"

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
    --validate-properties)
      validate_properties="${2:-}"
      [[ -n "$validate_properties" ]] || fail "--validate-properties requires a value"
      shift 2
      ;;
    --validate-deps)
      validate_deps="${2:-}"
      [[ -n "$validate_deps" ]] || fail "--validate-deps requires a value"
      shift 2
      ;;
    --validate-artifacts)
      validate_artifacts="${2:-}"
      [[ -n "$validate_artifacts" ]] || fail "--validate-artifacts requires a value"
      shift 2
      ;;
    --validate-mappings)
      validate_mappings="${2:-}"
      [[ -n "$validate_mappings" ]] || fail "--validate-mappings requires a value"
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

[[ -d "$project_root" ]] || fail "project root does not exist: ${project_root}"

require_bool --validate-properties "$validate_properties"
require_bool --validate-deps "$validate_deps"
require_bool --validate-artifacts "$validate_artifacts"
require_bool --validate-mappings "$validate_mappings"

if [[ -n "$loader" ]]; then
  case "$loader" in
    forge|neoforge|fabric) ;;
    *) fail "--loader must be forge|neoforge|fabric (got '${loader}')" ;;
  esac
fi

if [[ "$validate_properties" == "true" ]]; then
  bash "${SCRIPT_DIR}/validate-gradle-properties.sh" --project-root "$project_root" >/dev/null
fi

detect_out="$(bash "${SCRIPT_DIR}/quick-detect.sh" --project-root "$project_root")"
loader_multi="$(echo "$detect_out" | sed -n 's/^loader_multi=//p' | head -n 1)"
loader_type="$(echo "$detect_out" | sed -n 's/^loader_type=//p' | head -n 1)"
active_loaders="$(echo "$detect_out" | sed -n 's/^active_loaders=//p' | head -n 1)"

if [[ "$validate_deps" == "true" ]]; then
  bash "${SCRIPT_DIR}/validate-dependencies-yml.sh" --project-root "$project_root" >/dev/null
fi

declare -a loaders_to_check=()
if [[ -n "$loader" ]]; then
  loaders_to_check=("$loader")
else
  if [[ "$loader_multi" == "true" ]]; then
    IFS=',' read -r -a loaders_to_check <<<"$active_loaders"
  else
    loaders_to_check=("$loader_type")
  fi
fi

for l in "${loaders_to_check[@]}"; do
  l="$(trim "$l")"
  [[ -n "$l" ]] || continue

  if [[ "$validate_artifacts" == "true" ]]; then
    args=(--project-root "$project_root")
    if [[ "$loader_multi" == "true" || -n "$loader" ]]; then
      args+=(--loader "$l")
    fi
    bash "${SCRIPT_DIR}/validate-artifacts.sh" "${args[@]}" >/dev/null
  fi

  if [[ "$validate_mappings" == "true" ]]; then
    args=(--project-root "$project_root")
    if [[ "$loader_multi" == "true" || -n "$loader" ]]; then
      args+=(--loader "$l")
    fi
    bash "${SCRIPT_DIR}/validate-mappings.sh" "${args[@]}" >/dev/null
  fi
done

echo "health_check_status=pass"
