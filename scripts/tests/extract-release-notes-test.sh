#!/usr/bin/env bash
# extract-release-notes-test.sh
# Tests for scripts/extract-release-notes.sh

set -euo pipefail

fail() {
  local message="$1"
  echo "FAIL: ${message}" >&2
  exit 1
}

assert_ok() {
  local label="$1"
  shift
  if ! "$@" >/dev/null 2>&1; then
    fail "expected success: ${label}"
  fi
}

assert_fail() {
  local label="$1"
  shift
  if "$@" >/dev/null 2>&1; then
    fail "expected failure: ${label}"
  fi
}

readonly REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
readonly EXTRACTOR="${REPO_ROOT}/scripts/extract-release-notes.sh"

workdir="$(mktemp -d)"
cleanup() {
  rm -rf "$workdir"
}
trap cleanup EXIT

changelog="$workdir/RELEASE_CHANGELOG.md"
cat > "$changelog" <<'EOF'
# Changelog

## [Unreleased]

### Added

- TBD

## [1.2.0] - 2025-01-03

### Added

- New thing A

## [1.1.0] - 2025-01-02

### Fixed

- Fix B

## [1.0.0] - 2025-01-01

### Added

- Initial
EOF

# No previous release: only current section.
assert_ok "extract current only" bash "$EXTRACTOR" --changelog-file "$changelog" --current-version 1.2.0
out1="$($EXTRACTOR --changelog-file "$changelog" --current-version 1.2.0)"
echo "$out1" | grep -q "^## \[1\.2\.0\]" || fail "expected 1.2.0 heading"
echo "$out1" | grep -q "New thing A" || fail "expected 1.2.0 content"
echo "$out1" | grep -q "\[1\.1\.0\]" && fail "did not expect 1.1.0 content"

# With previous release: include current + intermediate versions down to previous (exclusive).
out2="$($EXTRACTOR --changelog-file "$changelog" --current-version 1.2.0 --previous-version 1.0.0)"
echo "$out2" | grep -q "\[1\.2\.0\]" || fail "expected 1.2.0 heading"
echo "$out2" | grep -q "\[1\.1\.0\]" || fail "expected 1.1.0 heading"
echo "$out2" | grep -q "\[1\.0\.0\]" && fail "did not expect 1.0.0 heading"

# Missing current version should fail.
assert_fail "missing current version" bash "$EXTRACTOR" --changelog-file "$changelog" --current-version 9.9.9

echo "OK"
