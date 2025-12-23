#!/usr/bin/env bash
# validate-dependencies-yml.sh
# Validates optional dependencies.yml (enrichment-only) and emits summary outputs.
#
# Contract:
# - dependencies.yml is OPTIONAL (local builds must not require it)
# - If present, it must be parseable and conform to schema expectations
# - "latest" resolution is NOT supported (no settings.auto_resolve_latest, no version.latest)
#
# Outputs key=value pairs to stdout suitable for appending to $GITHUB_OUTPUT.

set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  validate-dependencies-yml.sh [--project-root <path>] [--deps-file <path>]

Behavior:
- If the deps file does not exist: outputs dependencies_present=false and exits 0.
- If it exists: requires yq (mikefarah/yq v4), validates, outputs counts.
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

project_root="."
deps_file="dependencies.yml"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --project-root)
      project_root="${2:-}"
      [[ -n "$project_root" ]] || fail "--project-root requires a value"
      shift 2
      ;;
    --deps-file)
      deps_file="${2:-}"
      [[ -n "$deps_file" ]] || fail "--deps-file requires a value"
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

readonly deps_path="${project_root%/}/${deps_file}"

if [[ ! -f "$deps_path" ]]; then
  echo "dependencies_present=false"
  echo "dependencies_file=${deps_file}"
  exit 0
fi

require_tool yq

# Basic structural validation for runtime dependency entries.
# This keeps downloads deterministic and fail-fast when dependencies.yml exists.
missing_source_type_count="$(yq eval '[.dependencies.runtime[]? | select((.source.type // "") == "")] | length' "$deps_path")"
if [[ "$missing_source_type_count" != "0" ]]; then
  fail "dependencies.yml has runtime entries missing source.type (${missing_source_type_count})"
fi

# modrinth entries must include identifiers.modrinth_id and version.default.
missing_modrinth_id_count="$(yq eval '[.dependencies.runtime[]? | select(.source.type == "modrinth") | select((.identifiers.modrinth_id // "") == "")] | length' "$deps_path")"
if [[ "$missing_modrinth_id_count" != "0" ]]; then
  fail "dependencies.yml has modrinth runtime entries missing identifiers.modrinth_id (${missing_modrinth_id_count})"
fi

missing_modrinth_version_count="$(yq eval '[.dependencies.runtime[]? | select(.source.type == "modrinth") | select((.version.default // "") == "")] | length' "$deps_path")"
if [[ "$missing_modrinth_version_count" != "0" ]]; then
  fail "dependencies.yml has modrinth runtime entries missing version.default (${missing_modrinth_version_count})"
fi

# curseforge entries must include identifiers.curseforge_id and identifiers.curseforge_file_id.
missing_curseforge_id_count="$(yq eval '[.dependencies.runtime[]? | select(.source.type == "curseforge") | select((.identifiers.curseforge_id // "") == "")] | length' "$deps_path")"
if [[ "$missing_curseforge_id_count" != "0" ]]; then
  fail "dependencies.yml has curseforge runtime entries missing identifiers.curseforge_id (${missing_curseforge_id_count})"
fi

missing_curseforge_file_id_count="$(yq eval '[.dependencies.runtime[]? | select(.source.type == "curseforge") | select((.identifiers.curseforge_file_id // "") == "")] | length' "$deps_path")"
if [[ "$missing_curseforge_file_id_count" != "0" ]]; then
  fail "dependencies.yml has curseforge runtime entries missing identifiers.curseforge_file_id (${missing_curseforge_file_id_count})"
fi

# url entries must include source.url
missing_url_count="$(yq eval '[.dependencies.runtime[]? | select(.source.type == "url") | select((.source.url // "") == "")] | length' "$deps_path")"
if [[ "$missing_url_count" != "0" ]]; then
  fail "dependencies.yml has url runtime entries missing source.url (${missing_url_count})"
fi

schema_version="$(yq eval '.version // ""' "$deps_path")"
if [[ "$schema_version" != "1.0" ]]; then
  fail "Unsupported dependencies.yml schema version '${schema_version}' (expected '1.0')"
fi

# Disallow any "latest" behavior.
auto_latest="$(yq eval '.settings.auto_resolve_latest // false' "$deps_path")"
if [[ "$auto_latest" == "true" ]]; then
  fail "settings.auto_resolve_latest=true is not supported"
fi

# Reject any dependency entry using version.latest=true (anywhere in the file).
# NOTE: yq's `type` returns YAML tags (e.g., "!!map"), not jq-style "object".
latest_entries_count="$(yq eval '[.. | select(tag == "!!map" and has("version")) | .version.latest?] | map(select(. == true)) | length' "$deps_path")"
if [[ "$latest_entries_count" != "0" ]]; then
  fail "dependencies.yml contains version.latest=true entries (${latest_entries_count})"
fi

# Reject any dependency entry using version.default: latest
latest_default_count="$(yq eval '[.. | select(tag == "!!map" and has("version")) | .version.default?] | map(select(. == "latest")) | length' "$deps_path")"
if [[ "$latest_default_count" != "0" ]]; then
  fail "dependencies.yml contains version.default: latest entries (${latest_default_count})"
fi

runtime_count="$(yq eval '.dependencies.runtime | length' "$deps_path" 2>/dev/null || echo 0)"
development_count="$(yq eval '.dependencies.development | length' "$deps_path" 2>/dev/null || echo 0)"
optional_count="$(yq eval '.dependencies.optional | length' "$deps_path" 2>/dev/null || echo 0)"
incompatible_count="$(yq eval '.dependencies.incompatible | length' "$deps_path" 2>/dev/null || echo 0)"

# Ensure these are numbers (yq returns "null" when missing)
for v in runtime_count development_count optional_count incompatible_count; do
  value="${!v}"
  if [[ "$value" == "null" || -z "$value" ]]; then
    printf -v "$v" '%s' "0"
  fi
  if ! [[ "${!v}" =~ ^[0-9]+$ ]]; then
    fail "Invalid count parsed for ${v}: ${!v}"
  fi
done

echo "dependencies_present=true"
echo "dependencies_file=${deps_file}"
echo "dependencies_schema_version=${schema_version}"
echo "dependencies_runtime_count=${runtime_count}"
echo "dependencies_development_count=${development_count}"
echo "dependencies_optional_count=${optional_count}"
echo "dependencies_incompatible_count=${incompatible_count}"
