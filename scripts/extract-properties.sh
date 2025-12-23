#!/usr/bin/env bash
# extract-properties.sh
# Extracts values from gradle.properties in a deterministic way.
#
# v2 goals:
# - Presets (canonical vs all)
# - Output formats: env (key=value), json, yaml

set -euo pipefail

readonly SCRIPT_NAME="$(basename "$0")"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

usage() {
  cat <<'EOF'
Usage: extract-properties.sh [OPTIONS]

Options:
  --project-root <path>       Project root containing gradle.properties (default: .)
  --properties-file <path>    Properties file relative to project root (default: gradle.properties)
  --preset <canonical|all>    Output preset (default: canonical)
  --format <env|json|yaml>    Output format (default: env)
  --output <path>             Output file path, or '-' for stdout (default: -)
  -h, --help                  Show this help

Presets:
  canonical  Emits the canonical contract outputs (via quick-detect.sh):
             project_root, detected_loaders, loader_multi, loader_type, active_loaders,
             minecraft_version, mod_id, mod_version, java_version
  all        Emits all keys found in the properties file (simple key=value parsing).

Notes:
  - json output requires jq
  - yaml output requires yq (mikefarah/yq v4)
EOF
}

fail() {
  local message="$1"
  echo "ERROR: ${message}" >&2
  exit 1
}

require_tool() {
  local tool_name="$1"
  command -v "$tool_name" >/dev/null 2>&1 || fail "Required tool not found: ${tool_name}"
}

trim() {
  local s="$1"
  s="${s#${s%%[![:space:]]*}}"
  s="${s%${s##*[![:space:]]}}"
  printf '%s' "$s"
}

declare -A PROPS=()
declare -a ORDER=()

parse_properties_file() {
  local file_path="$1"

  [[ -f "$file_path" ]] || fail "Missing properties file: ${file_path}"

  local line
  while IFS='' read -r line || [[ -n "$line" ]]; do
    line="$(trim "$line")"
    [[ -n "$line" ]] || continue
    [[ "$line" != \#* ]] || continue

    if [[ "$line" != *"="* ]]; then
      fail "Invalid properties line (expected key=value): ${line}"
    fi

    local key="${line%%=*}"
    local value="${line#*=}"
    key="$(trim "$key")"
    value="$(trim "$value")"

    [[ -n "$key" ]] || fail "Invalid properties line (empty key): ${line}"

    if [[ -z "${PROPS[$key]+_}" ]]; then
      ORDER+=("$key")
    fi
    PROPS["$key"]="$value"
  done <"$file_path"
}

emit_env_kv() {
  local -n keys_ref=$1
  local -n kv_ref=$2

  local k
  for k in "${keys_ref[@]}"; do
    printf '%s=%s\n' "$k" "${kv_ref[$k]}"
  done
}

emit_json_kv() {
  local -n keys_ref=$1
  local -n kv_ref=$2

  require_tool jq

  {
    local k
    for k in "${keys_ref[@]}"; do
      printf '%s\t%s\n' "$k" "${kv_ref[$k]}"
    done
  } | jq -Rn '
    reduce (inputs | split("\t")) as $kv ({}; .[$kv[0]] = ($kv[1] // ""))
  '
}

project_root="."
properties_file="gradle.properties"
preset="canonical"
format="env"
output_path="-"

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
    --preset)
      preset="${2:-}"
      [[ -n "$preset" ]] || fail "--preset requires a value"
      shift 2
      ;;
    --format)
      format="${2:-}"
      [[ -n "$format" ]] || fail "--format requires a value"
      shift 2
      ;;
    --output)
      output_path="${2:-}"
      [[ -n "$output_path" ]] || fail "--output requires a value"
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

case "$preset" in
  canonical|all) ;;
  *) fail "--preset must be canonical|all (got ${preset})" ;;
esac

case "$format" in
  env|json|yaml) ;;
  *) fail "--format must be env|json|yaml (got ${format})" ;;
esac

readonly props_path="${project_root%/}/${properties_file}"

declare -A OUT=()
declare -a OUT_KEYS=()

if [[ "$preset" == "canonical" ]]; then
  detect_out="$(bash "${SCRIPT_DIR}/quick-detect.sh" --project-root "$project_root")"
  OUT_KEYS=(
    "project_root"
    "detected_loaders"
    "loader_multi"
    "loader_type"
    "active_loaders"
    "minecraft_version"
    "mod_id"
    "mod_version"
    "java_version"
  )

  for k in "${OUT_KEYS[@]}"; do
    OUT["$k"]="$(echo "$detect_out" | sed -n "s/^${k}=//p" | head -n 1)"
  done
else
  parse_properties_file "$props_path"
  OUT_KEYS=("${ORDER[@]}")
  for k in "${OUT_KEYS[@]}"; do
    OUT["$k"]="${PROPS[$k]}"
  done
fi

content=""
case "$format" in
  env)
    content="$(emit_env_kv OUT_KEYS OUT)"
    ;;
  json)
    content="$(emit_json_kv OUT_KEYS OUT)"
    ;;
  yaml)
    require_tool yq
    require_tool jq
    json_out="$(emit_json_kv OUT_KEYS OUT)"
    content="$(printf '%s' "$json_out" | yq -p=json -o=yaml -P)"
    ;;
esac

if [[ "$output_path" == "-" ]]; then
  printf '%s' "$content"
else
  mkdir -p "$(dirname "$output_path")"
  printf '%s' "$content" >"$output_path"
fi
