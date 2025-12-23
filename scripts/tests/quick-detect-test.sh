#!/usr/bin/env bash
# quick-detect-test.sh
# Minimal tests for scripts/quick-detect.sh

set -euo pipefail

readonly REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
readonly SCRIPT_UNDER_TEST="${REPO_ROOT}/scripts/quick-detect.sh"

fail() {
  local message="$1"
  echo "TEST ERROR: ${message}" >&2
  exit 1
}

assert_contains() {
  local haystack="$1"
  local needle="$2"
  echo "$haystack" | grep -Fq "$needle" || fail "expected output to contain: ${needle}"
}

assert_exit_code() {
  local expected="$1"
  shift

  set +e
  "$@" >/dev/null 2>&1
  local actual="$?"
  set -e

  [[ "$actual" == "$expected" ]] || fail "expected exit code ${expected}, got ${actual}"
}

tmp_dir=""
cleanup() {
  if [[ -n "${tmp_dir:-}" && -d "$tmp_dir" ]]; then
    rm -rf "$tmp_dir"
  fi
}
trap cleanup EXIT

tmp_dir="$(mktemp -d)"

# Case 1: minimal single-loader should succeed.
mkdir -p "${tmp_dir}/single"
cat >"${tmp_dir}/single/gradle.properties" <<'EOF'
minecraft_version=1.21.1
mod_id=examplemod
mod_version=0.1.0
java_version=21
loader_multi=false
loader_type=neoforge
EOF

output="$(${SCRIPT_UNDER_TEST} --project-root "${tmp_dir}/single")"
assert_contains "$output" "minecraft_version=1.21.1"
assert_contains "$output" "loader_multi=false"
assert_contains "$output" "active_loaders=neoforge"

# Case 2: neoforge gating should fail on 1.20.1.
mkdir -p "${tmp_dir}/bad_neoforge"
cat >"${tmp_dir}/bad_neoforge/gradle.properties" <<'EOF'
minecraft_version=1.20.1
mod_id=examplemod
mod_version=0.1.0
java_version=21
loader_multi=false
loader_type=neoforge
EOF
assert_exit_code 1 "${SCRIPT_UNDER_TEST}" --project-root "${tmp_dir}/bad_neoforge"

# Case 3: structure indicates multi-loader, but loader_multi=false should fail.
mkdir -p "${tmp_dir}/multi_mismatch/forge" "${tmp_dir}/multi_mismatch/fabric"
: >"${tmp_dir}/multi_mismatch/forge/build.gradle"
: >"${tmp_dir}/multi_mismatch/fabric/build.gradle"
cat >"${tmp_dir}/multi_mismatch/gradle.properties" <<'EOF'
minecraft_version=1.21.1
mod_id=examplemod
mod_version=0.1.0
java_version=21
loader_multi=false
loader_type=forge
EOF
assert_exit_code 1 "${SCRIPT_UNDER_TEST}" --project-root "${tmp_dir}/multi_mismatch"

echo "OK"
