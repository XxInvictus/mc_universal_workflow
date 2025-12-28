#!/usr/bin/env bash
# find-previous-release-tag-test.sh
# Tests for scripts/find-previous-release-tag.sh

set -euo pipefail

fail() {
  local message="$1"
  echo "FAIL: ${message}" >&2
  exit 1
}

assert_eq() {
  local label="$1"
  local expected="$2"
  local actual="$3"
  if [[ "$expected" != "$actual" ]]; then
    fail "${label}: expected '${expected}', got '${actual}'"
  fi
}

readonly REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
readonly FINDER="${REPO_ROOT}/scripts/find-previous-release-tag.sh"

workdir="$(mktemp -d)"
cleanup() {
  rm -rf "$workdir"
}
trap cleanup EXIT

tags_file="$workdir/tags.txt"
cat > "$tags_file" <<'EOF'
1.20.1-0.9.0
1.20.1-1.0.0
1.20.1-1.1.0
1.21.1-1.0.0
randomtag
1.20.1-2.0.0
EOF

# Previous for 1.20.1 current 1.2.0 should be 1.1.0
out="$($FINDER --repo owner/repo --minecraft-version 1.20.1 --current-mod-version 1.2.0 --tags-file "$tags_file")"
prev_mod="$(echo "$out" | sed -n 's/^previous_mod_version=//p')"
prev_tag="$(echo "$out" | sed -n 's/^previous_tag=//p')"
assert_eq "prev_mod_version" "1.1.0" "$prev_mod"
assert_eq "prev_tag" "1.20.1-1.1.0" "$prev_tag"

# Previous for 1.21.1 current 1.0.0 should be empty (only same version exists)
out2="$($FINDER --repo owner/repo --minecraft-version 1.21.1 --current-mod-version 1.0.0 --tags-file "$tags_file")"
prev_mod2="$(echo "$out2" | sed -n 's/^previous_mod_version=//p')"
assert_eq "prev_mod_version empty" "" "$prev_mod2"

# Non-strict version should return empty (maintainability rule)
out3="$($FINDER --repo owner/repo --minecraft-version 1.20.1 --current-mod-version 1.2.0-beta.1 --tags-file "$tags_file")"
prev_mod3="$(echo "$out3" | sed -n 's/^previous_mod_version=//p')"
assert_eq "prev_mod_version empty for prerelease" "" "$prev_mod3"

echo "OK"
