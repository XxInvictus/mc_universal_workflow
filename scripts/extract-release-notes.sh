#!/usr/bin/env bash
# extract-release-notes.sh
# Extracts release notes from a Keep a Changelog (1.0.0-style) changelog.
#
# By default, it extracts only the current version section.
# If a previous version is provided, it extracts the current version section and
# any unreleased intermediate version sections down to (but not including) the
# previous version.

set -euo pipefail

fail() {
  local message="$1"
  echo "ERROR: ${message}" >&2
  exit 1
}

usage() {
  cat <<'EOF'
Usage: extract-release-notes.sh [OPTIONS]

Options:
  --changelog-file <path>     Path to changelog file
  --current-version <x.y.z>   Current version to extract
  --previous-version <x.y.z>  Previous released version (optional)
  -h, --help                  Show this help

Behavior:
  - Extracts from the heading matching: "## [<version>] - YYYY-MM-DD"
  - If --previous-version is provided, extraction stops before that version's heading.
  - If --previous-version is not provided, extraction stops before the next version heading.
EOF
}

changelog_file=""
current_version=""
previous_version=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --changelog-file)
      changelog_file="${2:-}"
      shift 2
      ;;
    --current-version)
      current_version="${2:-}"
      shift 2
      ;;
    --previous-version)
      previous_version="${2:-}"
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

[[ -n "$changelog_file" ]] || fail "--changelog-file is required"
[[ -n "$current_version" ]] || fail "--current-version is required"
[[ -f "$changelog_file" ]] || fail "changelog file not found: ${changelog_file}"

current_prefix="## [${current_version}] - "

if [[ -n "$previous_version" ]]; then
  previous_prefix="## [${previous_version}] - "
else
  previous_prefix=""
fi

# Print from current heading until before previous heading (if provided) or until
# before the next version heading.
awk \
  -v current_prefix="$current_prefix" \
  -v prev_prefix="$previous_prefix" \
  '
    BEGIN { printing=0; found=0; start_line=0 }

    function is_release_heading(line) {
      return (line ~ /^##[[:space:]]+\[[0-9]+\.[0-9]+\.[0-9]+\][[:space:]]+-[[:space:]]+[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9][[:space:]]*$/)
    }

    !printing && index($0, current_prefix) == 1 && is_release_heading($0) {
      printing=1;
      found=1;
      start_line=NR;
      print;
      next;
    }

    printing && prev_prefix != "" && index($0, prev_prefix) == 1 && is_release_heading($0) {
      exit;
    }

    printing && prev_prefix == "" && NR != start_line && is_release_heading($0) {
      exit;
    }

    printing { print; }

    END {
      if (found == 0) exit 3;
    }
  ' "$changelog_file" || {
    status=$?
    if [[ $status -eq 3 ]]; then
      fail "current version heading not found for ${current_version} in ${changelog_file}"
    fi
    exit $status
  }
