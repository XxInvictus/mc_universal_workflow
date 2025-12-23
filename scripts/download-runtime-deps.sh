#!/usr/bin/env bash
# download-runtime-deps.sh
# Downloads runtime mod dependencies declared in dependencies.yml into a destination mods folder.
#
# Sources supported (no secrets required):
# - modrinth (api.modrinth.com)
# - curseforge (api.curse.tools)
# - url (direct URL, including file://)
#
# Contract:
# - dependencies.yml is optional; if missing, exits 0.
# - No "latest" resolution; versions must be pinned.
# - Downloads are the published mod jars (not dev/build artifacts from Maven repos).

set -euo pipefail

usage() {
  cat <<'EOF'
Usage: download-runtime-deps.sh [OPTIONS]

Options:
  --project-root <path>       Project root containing dependencies.yml (default: .)
  --deps-file <path>          Path to dependencies.yml relative to project root (default: dependencies.yml)
  --loader <forge|neoforge|fabric>
                              Loader being tested (required)
  --minecraft-version <ver>   Minecraft version being tested (required)
  --dest-dir <path>           Destination directory for downloaded jars (default: run/mods)
  --user-agent <ua>           User-Agent header for API requests
                              (default: XxInvictus/mc_universal_workflow)
  -h, --help                  Show this help

Outputs (key=value):
  dependencies_present
  downloaded_count
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

json_escape() {
  # Prints a JSON string literal (without surrounding quotes) for a single value.
  # Uses jq for correctness.
  local value="$1"
  jq -rn --arg v "$value" '$v'
}

should_include_dep() {
  local dep_json="$1"
  local loader="$2"
  local minecraft_version="$3"

  # loaders filter
  local loaders_json
  loaders_json="$(echo "$dep_json" | jq -c '.loaders? // empty')"
  if [[ -n "$loaders_json" && "$loaders_json" != "null" ]]; then
    if [[ "$(echo "$dep_json" | jq -r --arg l "$loader" '(.loaders? // []) | any(. == $l)')" != "true" ]]; then
      return 1
    fi
  fi

  # minecraft filter
  local mc_json
  mc_json="$(echo "$dep_json" | jq -c '.minecraft? // empty')"
  if [[ -n "$mc_json" && "$mc_json" != "null" ]]; then
    if [[ "$(echo "$dep_json" | jq -r --arg mc "$minecraft_version" '(.minecraft? // []) | any(. == $mc) or any(. == "*")')" != "true" ]]; then
      return 1
    fi
  fi

  return 0
}

download_url_to_file() {
  local url="$1"
  local dest_file="$2"
  local user_agent="$3"

  mkdir -p "$(dirname "$dest_file")"

  local tmp
  tmp="${dest_file}.tmp"

  curl -fsSL -H "User-Agent: ${user_agent}" -L "$url" -o "$tmp"

  if [[ ! -s "$tmp" ]]; then
    rm -f "$tmp"
    fail "downloaded file is empty: ${url}"
  fi

  mv "$tmp" "$dest_file"
}

verify_sha1() {
  local file_path="$1"
  local expected_sha1="$2"

  if [[ -z "$expected_sha1" ]]; then
    return 0
  fi

  require_tool sha1sum

  local actual
  actual="$(sha1sum "$file_path" | awk '{print $1}')"
  if [[ "$actual" != "$expected_sha1" ]]; then
    fail "sha1 mismatch for $(basename "$file_path"): expected=${expected_sha1} actual=${actual}"
  fi
}

download_modrinth() {
  local dep_json="$1"
  local loader="$2"
  local minecraft_version="$3"
  local dest_dir="$4"
  local user_agent="$5"

  local project_id
  project_id="$(echo "$dep_json" | jq -r '.identifiers.modrinth_id // empty')"
  [[ -n "$project_id" ]] || fail "modrinth dependency missing identifiers.modrinth_id"

  local desired
  desired="$(echo "$dep_json" | jq -r '.version.default // empty')"
  [[ -n "$desired" ]] || fail "modrinth dependency '${project_id}' missing version.default"

  local versions_json
  versions_json="$(curl -fsSL -H "User-Agent: ${user_agent}" \
    --get "https://api.modrinth.com/v2/project/${project_id}/version" \
    --data-urlencode "loaders=[\"${loader}\"]" \
    --data-urlencode "game_versions=[\"${minecraft_version}\"]")"

  local selected
  selected="$(echo "$versions_json" | jq -c --arg v "$desired" 'map(select(.version_number == $v)) | .[0] // empty')"
  [[ -n "$selected" ]] || fail "modrinth dependency '${project_id}' has no version_number='${desired}' for loader=${loader} mc=${minecraft_version}"

  local file_url
  local file_name
  local file_sha1

  file_url="$(echo "$selected" | jq -r '(.files | map(select(.primary == true)) | .[0].url) // .files[0].url')"
  file_name="$(echo "$selected" | jq -r '(.files | map(select(.primary == true)) | .[0].filename) // .files[0].filename')"
  file_sha1="$(echo "$selected" | jq -r '(.files | map(select(.primary == true)) | .[0].hashes.sha1) // .files[0].hashes.sha1 // empty')"

  [[ -n "$file_url" && -n "$file_name" ]] || fail "modrinth dependency '${project_id}' returned no downloadable file"

  local dest_file
  dest_file="${dest_dir%/}/${file_name}"

  download_url_to_file "$file_url" "$dest_file" "$user_agent"
  verify_sha1 "$dest_file" "$file_sha1"
}

curseforge_loader_label() {
  local loader="$1"
  case "$loader" in
    forge) echo "Forge" ;;
    neoforge) echo "NeoForge" ;;
    fabric) echo "Fabric" ;;
    *) fail "unsupported loader for curseforge mapping: ${loader}" ;;
  esac
}

download_curseforge() {
  local dep_json="$1"
  local loader="$2"
  local minecraft_version="$3"
  local dest_dir="$4"
  local user_agent="$5"

  local mod_id
  local file_id
  mod_id="$(echo "$dep_json" | jq -r '.identifiers.curseforge_id // empty')"
  file_id="$(echo "$dep_json" | jq -r '.identifiers.curseforge_file_id // empty')"

  [[ -n "$mod_id" ]] || fail "curseforge dependency missing identifiers.curseforge_id"
  [[ -n "$file_id" ]] || fail "curseforge dependency '${mod_id}' missing identifiers.curseforge_file_id (required for deterministic downloads)"

  local file_json
  file_json="$(curl -fsSL -H "User-Agent: ${user_agent}" "https://api.curse.tools/v1/cf/mods/${mod_id}/files/${file_id}")"

  local download_url
  local file_name
  local sha1
  download_url="$(echo "$file_json" | jq -r '.data.downloadUrl // empty')"
  file_name="$(echo "$file_json" | jq -r '.data.fileName // empty')"
  sha1="$(echo "$file_json" | jq -r '.data.hashes[]? | select(.algo==1) | .value' | head -n 1)"

  [[ -n "$download_url" && -n "$file_name" ]] || fail "curseforge dependency '${mod_id}' file_id=${file_id} returned no downloadUrl/fileName"

  # Ensure the file matches the expected loader + minecraft version.
  local expected_label
  expected_label="$(curseforge_loader_label "$loader")"

  local matches_mc
  local matches_loader
  matches_mc="$(echo "$file_json" | jq -r --arg mc "$minecraft_version" '(.data.gameVersions // []) | any(. == $mc)')"
  matches_loader="$(echo "$file_json" | jq -r --arg l "$expected_label" '(.data.gameVersions // []) | any(. == $l)')"

  if [[ "$matches_mc" != "true" || "$matches_loader" != "true" ]]; then
    fail "curseforge dependency '${mod_id}' file_id=${file_id} does not match loader=${expected_label} and mc=${minecraft_version}"
  fi

  local dest_file
  dest_file="${dest_dir%/}/${file_name}"

  download_url_to_file "$download_url" "$dest_file" "$user_agent"
  verify_sha1 "$dest_file" "$sha1"
}

download_direct_url() {
  local dep_json="$1"
  local dest_dir="$2"
  local user_agent="$3"

  local url
  url="$(echo "$dep_json" | jq -r '.source.url // empty')"
  [[ -n "$url" ]] || fail "url dependency missing source.url"

  local file_name
  file_name="$(echo "$dep_json" | jq -r '.source.filename // empty')"
  if [[ -z "$file_name" ]]; then
    file_name="$(basename "${url%%\?*}")"
  fi
  [[ -n "$file_name" ]] || fail "unable to determine filename for url dependency: ${url}"

  local dest_file
  dest_file="${dest_dir%/}/${file_name}"

  download_url_to_file "$url" "$dest_file" "$user_agent"

  local sha1
  sha1="$(echo "$dep_json" | jq -r '.hashes.sha1 // empty')"
  verify_sha1 "$dest_file" "$sha1"
}

project_root="."
deps_file="dependencies.yml"
loader=""
minecraft_version=""
dest_dir="run/mods"
user_agent="XxInvictus/mc_universal_workflow"

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
    --loader)
      loader="${2:-}"
      [[ -n "$loader" ]] || fail "--loader requires a value"
      shift 2
      ;;
    --minecraft-version)
      minecraft_version="${2:-}"
      [[ -n "$minecraft_version" ]] || fail "--minecraft-version requires a value"
      shift 2
      ;;
    --dest-dir)
      dest_dir="${2:-}"
      [[ -n "$dest_dir" ]] || fail "--dest-dir requires a value"
      shift 2
      ;;
    --user-agent)
      user_agent="${2:-}"
      [[ -n "$user_agent" ]] || fail "--user-agent requires a value"
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

case "$loader" in
  forge|neoforge|fabric) ;;
  *) fail "--loader must be one of forge|neoforge|fabric" ;;
esac

[[ -n "$minecraft_version" ]] || fail "--minecraft-version is required"

readonly deps_path="${project_root%/}/${deps_file}"

if [[ ! -f "$deps_path" ]]; then
  echo "dependencies_present=false"
  echo "downloaded_count=0"
  exit 0
fi

require_tool yq
require_tool jq
require_tool curl

# Validate + convert runtime dependencies list to JSON for robust parsing.
runtime_json="$(yq eval -o=json '.dependencies.runtime // []' "$deps_path")"

if [[ "$(echo "$runtime_json" | jq -r 'type')" != "array" ]]; then
  fail "dependencies.yml .dependencies.runtime must be an array"
fi

mkdir -p "$dest_dir"

downloaded_count=0

while IFS= read -r dep; do
  [[ -n "$dep" ]] || continue

  if ! should_include_dep "$dep" "$loader" "$minecraft_version"; then
    continue
  fi

  dep_type="$(echo "$dep" | jq -r '.source.type // empty')"
  [[ -n "$dep_type" ]] || fail "dependency entry missing source.type"

  case "$dep_type" in
    modrinth)
      download_modrinth "$dep" "$loader" "$minecraft_version" "$dest_dir" "$user_agent"
      downloaded_count=$((downloaded_count + 1))
      ;;
    curseforge)
      download_curseforge "$dep" "$loader" "$minecraft_version" "$dest_dir" "$user_agent"
      downloaded_count=$((downloaded_count + 1))
      ;;
    url)
      download_direct_url "$dep" "$dest_dir" "$user_agent"
      downloaded_count=$((downloaded_count + 1))
      ;;
    *)
      fail "unsupported dependency source.type='${dep_type}' (supported: modrinth|curseforge|url)"
      ;;
  esac
done < <(echo "$runtime_json" | jq -c '.[]')

echo "dependencies_present=true"
echo "downloaded_count=${downloaded_count}"
