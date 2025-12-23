#!/usr/bin/env bash
# validate-gradle-properties.sh
# Validates gradle.properties shape beyond "required keys exist":
# - All non-comment lines must be key=value
# - Keys must be lower_snake_case: ^[a-z][a-z0-9_]*$
# - No duplicate keys
# - Canonical contract keys are present and sane

set -euo pipefail

readonly SCRIPT_NAME="$(basename "$0")"

usage() {
  cat <<'EOF'
Usage: validate-gradle-properties.sh [OPTIONS]

Options:
  --project-root <path>       Project root containing gradle.properties (default: .)
  --properties-file <path>    Properties file relative to project root (default: gradle.properties)
  -h, --help                  Show this help

Outputs (key=value):
  validation_status (pass)
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

project_root="."
properties_file="gradle.properties"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --project-root)
      project_root="${2:-}"
      [[ -n "$project_root" ]] || fail "--project-root requires a value"
      shift 2
      ;;
    --properties-file)
      properties_file="${2:-}"
      [[ -n "$properties_file" ]] || fail "--properties-file requires a value"
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

readonly props_path="${project_root%/}/${properties_file}"
[[ -f "$props_path" ]] || fail "Missing required file: ${props_path}"

declare -A PROPS=()
declare -A SEEN=()

line_no=0
while IFS='' read -r raw_line || [[ -n "$raw_line" ]]; do
  line_no=$((line_no + 1))
  line="$(trim "$raw_line")"
  [[ -n "$line" ]] || continue
  [[ "$line" != \#* ]] || continue

  if [[ "$line" != *"="* ]]; then
    fail "Invalid line ${line_no} in ${properties_file} (expected key=value): ${raw_line}"
  fi

  key="${line%%=*}"
  value="${line#*=}"
  key="$(trim "$key")"
  value="$(trim "$value")"

  [[ -n "$key" ]] || fail "Invalid line ${line_no} in ${properties_file} (empty key)"

  if ! [[ "$key" =~ ^[a-z][a-z0-9_]*$ ]]; then
    fail "Invalid key '${key}' on line ${line_no}; keys must be lower_snake_case"
  fi

  if [[ -n "${SEEN[$key]+_}" ]]; then
    fail "Duplicate key '${key}' in ${properties_file} (line ${line_no})"
  fi
  SEEN["$key"]=1
  PROPS["$key"]="$value"
done <"$props_path"

require_prop() {
  local k="$1"
  local v="${PROPS[$k]-}"
  [[ -n "$v" ]] || fail "Missing required property '${k}' in ${properties_file}"
  printf '%s' "$v"
}

minecraft_version="$(require_prop "minecraft_version")"
mod_id="$(require_prop "mod_id")"
mod_version="$(require_prop "mod_version")"
loader_multi="$(require_prop "loader_multi")"

case "$loader_multi" in
  true|false) ;;
  *) fail "loader_multi must be true|false (got '${loader_multi}')" ;;
esac

loader_type=""
active_loaders=""
if [[ "$loader_multi" == "true" ]]; then
  active_loaders="$(require_prop "active_loaders")"

  IFS=',' read -r -a loaders <<<"$active_loaders"
  if [[ "${#loaders[@]}" -lt 2 ]]; then
    fail "active_loaders must list at least 2 loaders when loader_multi=true (got '${active_loaders}')"
  fi

  declare -A seen_loader=()
  for l in "${loaders[@]}"; do
    l="$(trim "$l")"
    [[ -n "$l" ]] || fail "active_loaders contains an empty entry"
    case "$l" in
      forge|neoforge|fabric) ;;
      *) fail "Unsupported loader in active_loaders: ${l}" ;;
    esac
    if [[ -n "${seen_loader[$l]+_}" ]]; then
      fail "active_loaders contains duplicate loader: ${l}"
    fi
    seen_loader["$l"]=1
  done
else
  loader_type="$(require_prop "loader_type")"
  case "$loader_type" in
    forge|neoforge|fabric) ;;
    *) fail "loader_type must be one of forge|neoforge|fabric (got '${loader_type}')" ;;
  esac
fi

[[ -n "$minecraft_version" ]] || fail "minecraft_version cannot be empty"
[[ -n "$mod_id" ]] || fail "mod_id cannot be empty"
[[ -n "$mod_version" ]] || fail "mod_version cannot be empty"

echo "validation_status=pass"
