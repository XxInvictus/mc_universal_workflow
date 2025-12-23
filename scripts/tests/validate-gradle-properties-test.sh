#!/usr/bin/env bash
# validate-gradle-properties-test.sh
# Minimal tests for scripts/validate-gradle-properties.sh

set -euo pipefail

readonly REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
readonly SCRIPT_UNDER_TEST="${REPO_ROOT}/scripts/validate-gradle-properties.sh"

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

# Case 1: valid
mkdir -p "${tmp_dir}/valid"
cat >"${tmp_dir}/valid/gradle.properties" <<'EOF'
minecraft_version=1.21.1
mod_id=examplemod
mod_version=0.1.0
loader_multi=false
loader_type=forge
EOF

out1="$(${SCRIPT_UNDER_TEST} --project-root "${tmp_dir}/valid")"
assert_contains "$out1" "validation_status=pass"

# Case 2: duplicate key fails
mkdir -p "${tmp_dir}/dup"
cat >"${tmp_dir}/dup/gradle.properties" <<'EOF'
minecraft_version=1.21.1
minecraft_version=1.21.1
mod_id=examplemod
mod_version=0.1.0
loader_multi=false
loader_type=forge
EOF
assert_exit_code 1 "${SCRIPT_UNDER_TEST}" --project-root "${tmp_dir}/dup"

# Case 3: invalid key name fails
mkdir -p "${tmp_dir}/bad_key"
cat >"${tmp_dir}/bad_key/gradle.properties" <<'EOF'
minecraft_version=1.21.1
Mod_ID=examplemod
mod_version=0.1.0
loader_multi=false
loader_type=forge
EOF
assert_exit_code 1 "${SCRIPT_UNDER_TEST}" --project-root "${tmp_dir}/bad_key"

# Case 4: multi-loader requires 2+ loaders
mkdir -p "${tmp_dir}/multi_one"
cat >"${tmp_dir}/multi_one/gradle.properties" <<'EOF'
minecraft_version=1.21.1
mod_id=examplemod
mod_version=0.1.0
loader_multi=true
active_loaders=forge
EOF
assert_exit_code 1 "${SCRIPT_UNDER_TEST}" --project-root "${tmp_dir}/multi_one"

# Case 5: invalid loader_type fails
mkdir -p "${tmp_dir}/bad_loader"
cat >"${tmp_dir}/bad_loader/gradle.properties" <<'EOF'
minecraft_version=1.21.1
mod_id=examplemod
mod_version=0.1.0
loader_multi=false
loader_type=quilt
EOF
assert_exit_code 1 "${SCRIPT_UNDER_TEST}" --project-root "${tmp_dir}/bad_loader"

echo "OK"
