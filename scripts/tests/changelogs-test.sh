#!/usr/bin/env bash
# changelogs-test.sh
# Tests for scripts/validate-changelogs.sh

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
readonly VALIDATE="${REPO_ROOT}/scripts/validate-changelogs.sh"

workdir="$(mktemp -d)"
cleanup() {
  rm -rf "$workdir"
}
trap cleanup EXIT

mkdir -p "$workdir/pass"
cp "${REPO_ROOT}/templates/CHANGELOG.md" "$workdir/pass/CHANGELOG.md"
cp "${REPO_ROOT}/templates/RELEASE_CHANGELOG.md" "$workdir/pass/RELEASE_CHANGELOG.md"
assert_ok "template files pass" bash "$VALIDATE" --project-root "$workdir/pass"

mkdir -p "$workdir/missing"
assert_fail "missing files fail" bash "$VALIDATE" --project-root "$workdir/missing"

mkdir -p "$workdir/bad"
cat > "$workdir/bad/CHANGELOG.md" <<'EOF'
# Changelog

## [Unreleased]
- Something
EOF
cat > "$workdir/bad/RELEASE_CHANGELOG.md" <<'EOF'
# Changelog

## [Unreleased]
- Something
EOF
assert_fail "missing released version headings fail" bash "$VALIDATE" --project-root "$workdir/bad"

echo "OK"
