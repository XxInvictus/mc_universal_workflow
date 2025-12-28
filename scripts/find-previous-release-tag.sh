#!/usr/bin/env bash
# find-previous-release-tag.sh
# Finds the previous published release tag for a given Minecraft version.
#
# Tags are expected to be in the form:
#   ${minecraft_version}-${mod_version}
# where mod_version is SemVer-like (x.y.z).
#
# Output (to GITHUB_OUTPUT):
#   previous_tag
#   previous_mod_version

set -euo pipefail

fail() {
  local message="$1"
  echo "ERROR: ${message}" >&2
  exit 1
}

usage() {
  cat <<'EOF'
Usage: find-previous-release-tag.sh [OPTIONS]

Options:
  --repo <owner/repo>            GitHub repo (defaults to GITHUB_REPOSITORY)
  --minecraft-version <value>    Minecraft version prefix (e.g., 1.20.1)
  --current-mod-version <x.y.z>  Current mod version (e.g., 1.2.3)
  --tags-file <path>             Optional file containing tag names (one per line) for offline tests
  -h, --help                     Show this help

Notes:
  - Uses `gh api` when --tags-file is not provided.
  - Only considers tags with the exact prefix "<minecraft-version>-".
  - Only considers mod versions that match strict x.y.z numeric SemVer.
EOF
}

repo="${GITHUB_REPOSITORY:-}"
mc_version=""
current_mod_version=""
tags_file=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo)
      repo="${2:-}"
      shift 2
      ;;
    --minecraft-version)
      mc_version="${2:-}"
      shift 2
      ;;
    --current-mod-version)
      current_mod_version="${2:-}"
      shift 2
      ;;
    --tags-file)
      tags_file="${2:-}"
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

[[ -n "$repo" ]] || fail "--repo is required (or set GITHUB_REPOSITORY)"
[[ -n "$mc_version" ]] || fail "--minecraft-version is required"
[[ -n "$current_mod_version" ]] || fail "--current-mod-version is required"

if [[ ! "$current_mod_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  # We intentionally keep this strict for maintainability and predictable ordering.
  echo "previous_tag="
  echo "previous_mod_version="
  exit 0
fi

prefix="${mc_version}-"

get_tags() {
  if [[ -n "$tags_file" ]]; then
    [[ -f "$tags_file" ]] || fail "tags file not found: ${tags_file}"
    cat "$tags_file"
    return 0
  fi

  if ! command -v gh >/dev/null 2>&1; then
    # On self-hosted runners gh may not exist; treat as no previous tags.
    return 0
  fi

  # Requires GH_TOKEN (or GITHUB_TOKEN) to be available in env.
  gh api "repos/${repo}/tags?per_page=100" --paginate --jq '.[].name' 2>/dev/null || true
}

pad_semver_key() {
  # Prints a sortable numeric key for x.y.z
  local v="$1"
  local major minor patch
  IFS='.' read -r major minor patch <<< "$v"
  printf '%05d%05d%05d' "$major" "$minor" "$patch"
}

current_key="$(pad_semver_key "$current_mod_version")"

best_key=""
best_version=""

while IFS= read -r tag; do
  [[ -n "$tag" ]] || continue
  [[ "$tag" == ${prefix}* ]] || continue

  mod_version="${tag#${prefix}}"
  [[ "$mod_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || continue

  key="$(pad_semver_key "$mod_version")"
  # Only consider versions strictly less than current.
  if [[ "$key" < "$current_key" ]]; then
    if [[ -z "$best_key" || "$key" > "$best_key" ]]; then
      best_key="$key"
      best_version="$mod_version"
    fi
  fi

done < <(get_tags)

if [[ -n "$best_version" ]]; then
  echo "previous_tag=${prefix}${best_version}"
  echo "previous_mod_version=${best_version}"
else
  echo "previous_tag="
  echo "previous_mod_version="
fi
