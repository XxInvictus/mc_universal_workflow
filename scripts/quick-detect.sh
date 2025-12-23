#!/usr/bin/env bash
# quick-detect.sh
# Fast project structure detection + canonical property validation (migration-only).
#
# Intended usage:
#   - From GitHub Actions on ubuntu runners
#   - From composite actions in this repo
#
# Outputs:
#   Writes key=value pairs to stdout suitable for appending to $GITHUB_OUTPUT.

set -euo pipefail

readonly SCRIPT_NAME="$(basename "$0")"

usage() {
  cat <<'EOF'
Usage:
  quick-detect.sh [--project-root <path>]

Detects loader structure from project layout and validates required canonical gradle.properties keys.

Outputs key=value pairs to stdout.
EOF
}

fail() {
  local message="$1"
  echo "ERROR: ${message}" >&2
  exit 1
}

require_file() {
  local path="$1"
  [[ -f "$path" ]] || fail "Missing required file: ${path}"
}

# Reads a Gradle property from gradle.properties (key=value).
# - Ignores commented lines
# - Returns empty if missing
read_gradle_prop() {
  local file_path="$1"
  local key="$2"

  # Grep is sufficient here because the canonical contract is simple key=value.
  # We intentionally do not attempt to evaluate Gradle expressions.
  local line
  line="$(grep -E "^[[:space:]]*${key}=" "$file_path" | head -n 1 || true)"
  if [[ -z "$line" ]]; then
    echo ""
    return 0
  fi

  # Strip everything up to first '=' and trim surrounding whitespace.
  local value
  value="${line#*=}"
  value="$(echo "$value" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
  echo "$value"
}

require_prop() {
  local file_path="$1"
  local key="$2"

  local value
  value="$(read_gradle_prop "$file_path" "$key")"
  [[ -n "$value" ]] || fail "Missing required property '${key}' in ${file_path}"
  echo "$value"
}

version_ge() {
  # Returns success if $1 >= $2.
  local version_a="$1"
  local version_b="$2"
  [[ "$(printf '%s\n%s\n' "$version_b" "$version_a" | sort -V | head -n 1)" == "$version_b" ]]
}

detect_loaders_from_structure() {
  local root_dir="$1"
  local -a loaders
  loaders=()

  # Structure-authoritative: loader module directories with build.gradle.
  local dir
  for dir in forge neoforge fabric; do
    if [[ -d "${root_dir}/${dir}" && -f "${root_dir}/${dir}/build.gradle" ]]; then
      loaders+=("$dir")
    fi
  done

  (IFS=,; echo "${loaders[*]}")
}

project_root="."

while [[ $# -gt 0 ]]; do
  case "$1" in
    --project-root)
      project_root="${2:-}"
      [[ -n "$project_root" ]] || fail "--project-root requires a value"
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

readonly project_root

if [[ ! -d "$project_root" ]]; then
  fail "project root does not exist: ${project_root}"
fi

readonly gradle_properties_path="${project_root%/}/gradle.properties"
require_file "$gradle_properties_path"

minecraft_version="$(require_prop "$gradle_properties_path" "minecraft_version")"
mod_id="$(require_prop "$gradle_properties_path" "mod_id")"
mod_version="$(require_prop "$gradle_properties_path" "mod_version")"

loader_multi="$(require_prop "$gradle_properties_path" "loader_multi")"
loader_type=""
active_loaders=""

if [[ "$loader_multi" == "true" ]]; then
  active_loaders="$(require_prop "$gradle_properties_path" "active_loaders")"
else
  loader_type="$(require_prop "$gradle_properties_path" "loader_type")"
  active_loaders="$loader_type"
fi

# Structure-authoritative loader discovery.
detected_loaders="$(detect_loaders_from_structure "$project_root")"

# Enforce multi-loader declaration if structure contains multiple loader modules.
detected_loader_count=0
if [[ -n "$detected_loaders" ]]; then
  detected_loader_count="$(echo "$detected_loaders" | awk -F',' '{print NF}')"
fi

if [[ "$detected_loader_count" -ge 2 && "$loader_multi" != "true" ]]; then
  fail "Structure indicates multi-loader (${detected_loaders}) but loader_multi is not true"
fi

# NeoForge gating.
if echo ",${active_loaders}," | grep -q ",neoforge,"; then
  if ! version_ge "$minecraft_version" "1.20.4"; then
    fail "NeoForge requires minecraft_version >= 1.20.4 (got ${minecraft_version})"
  fi
fi

# Output contract.
echo "project_root=${project_root}"
echo "detected_loaders=${detected_loaders}"
echo "loader_multi=${loader_multi}"
echo "loader_type=${loader_type}"
echo "active_loaders=${active_loaders}"
echo "minecraft_version=${minecraft_version}"
echo "mod_id=${mod_id}"
echo "mod_version=${mod_version}"
