#!/usr/bin/env bash
# validate-changelogs.sh
# Validates changelog format in consumer repos.
#
# CHANGELOG.md: full development/technical details
# RELEASE_CHANGELOG.md: user-facing concise changelog (still complete release history)

set -euo pipefail

readonly SCRIPT_NAME="$(basename "$0")"

usage() {
  cat <<'EOF'
Usage: validate-changelogs.sh [OPTIONS]

Options:
  --project-root <path>   Project root containing changelog files (default: .)
  -h, --help              Show this help

Checks:
  - Both files follow Keep a Changelog structure (https://keepachangelog.com/en/1.0.0/)
EOF
}

fail() {
  local message="$1"
  echo "ERROR: ${message}" >&2
  exit 1
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

[[ -d "$project_root" ]] || fail "project root does not exist: ${project_root}"

changelog_path="${project_root%/}/CHANGELOG.md"
release_changelog_path="${project_root%/}/RELEASE_CHANGELOG.md"

[[ -f "$changelog_path" ]] || fail "Missing required CHANGELOG.md at project root"
[[ -f "$release_changelog_path" ]] || fail "Missing required RELEASE_CHANGELOG.md at project root"

# Keep a Changelog structure checks.
# - Require '## [Unreleased]' in both.
# - Require at least one released version heading in both: '## [x.y.z] - YYYY-MM-DD'
unreleased_re='^##[[:space:]]+\[Unreleased\][[:space:]]*$'
version_re='^##[[:space:]]+\[[0-9]+\.[0-9]+\.[0-9]+\][[:space:]]+-[[:space:]]+[0-9]{4}-[0-9]{2}-[0-9]{2}[[:space:]]*$'

grep -qE "$unreleased_re" "$changelog_path" \
  || fail "CHANGELOG.md must contain '## [Unreleased]' (Keep a Changelog 1.0.0)"
grep -qE "$unreleased_re" "$release_changelog_path" \
  || fail "RELEASE_CHANGELOG.md must contain '## [Unreleased]' (Keep a Changelog 1.0.0)"

grep -qE "$version_re" "$changelog_path" \
  || fail "CHANGELOG.md must contain at least one released version heading like '## [1.2.3] - 2025-01-31'"
grep -qE "$version_re" "$release_changelog_path" \
  || fail "RELEASE_CHANGELOG.md must contain at least one released version heading like '## [1.2.3] - 2025-01-31'"

echo "changelog_validation=pass"
