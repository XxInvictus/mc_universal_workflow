#!/usr/bin/env bash
# compute-artifact-path.sh
# Computes the enforced artifact path based on canonical gradle.properties values.
#
# Contract (no custom patterns):
# - Single-module: build/libs/${mod_id}-${loader}-${minecraft_version}-${mod_version}.jar
# - Multi-loader:  ${loader}/build/libs/${mod_id}-${loader}-${minecraft_version}-${mod_version}.jar
#
# Outputs key=value pairs to stdout suitable for appending to $GITHUB_OUTPUT.

set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  compute-artifact-path.sh --project-root <path> [--loader <forge|neoforge|fabric>]

Notes:
- For single-loader projects, --loader is optional (defaults to active loader).
- For multi-loader projects (loader_multi=true), --loader is required.
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

read_gradle_prop() {
  local file_path="$1"
  local key="$2"

  local line
  line="$(grep -E "^[[:space:]]*${key}=" "$file_path" | head -n 1 || true)"
  if [[ -z "$line" ]]; then
    echo ""
    return 0
  fi

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

contains_csv_item() {
  local csv="$1"
  local item="$2"
  echo ",${csv}," | grep -Fq ",${item},"
}

project_root=""
loader=""

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

readonly gradle_properties_path="${project_root%/}/gradle.properties"
require_file "$gradle_properties_path"

minecraft_version="$(require_prop "$gradle_properties_path" "minecraft_version")"
mod_id="$(require_prop "$gradle_properties_path" "mod_id")"
mod_version="$(require_prop "$gradle_properties_path" "mod_version")"
loader_multi="$(require_prop "$gradle_properties_path" "loader_multi")"

active_loaders=""
if [[ "$loader_multi" == "true" ]]; then
  active_loaders="$(require_prop "$gradle_properties_path" "active_loaders")"
  [[ -n "$loader" ]] || fail "--loader is required when loader_multi=true"
  contains_csv_item "$active_loaders" "$loader" || fail "--loader '${loader}' is not in active_loaders (${active_loaders})"
else
  active_loaders="$(require_prop "$gradle_properties_path" "loader_type")"
  if [[ -z "$loader" ]]; then
    loader="$active_loaders"
  fi
  [[ "$loader" == "$active_loaders" ]] || fail "--loader '${loader}' does not match loader_type (${active_loaders})"
fi

case "$loader" in
  forge|neoforge|fabric) ;;
  *) fail "invalid loader '${loader}' (expected forge|neoforge|fabric)" ;;
esac

artifact_file=""
artifact_path=""
artifact_dir=""

if [[ "$loader_multi" == "true" ]]; then
  artifact_file="${mod_id}-${loader}-${minecraft_version}-${mod_version}.jar"
  artifact_dir="${loader}/build/libs"
  artifact_path="${artifact_dir}/${artifact_file}"
else
  artifact_file="${mod_id}-${loader}-${minecraft_version}-${mod_version}.jar"
  artifact_dir="build/libs"
  artifact_path="${artifact_dir}/${artifact_file}"
fi

echo "project_root=${project_root}"
echo "loader_multi=${loader_multi}"
echo "active_loaders=${active_loaders}"
echo "loader=${loader}"
echo "minecraft_version=${minecraft_version}"
echo "mod_id=${mod_id}"
echo "mod_version=${mod_version}"
echo "artifact_dir=${artifact_dir}"
echo "artifact_file=${artifact_file}"
echo "artifact_path=${artifact_path}"
