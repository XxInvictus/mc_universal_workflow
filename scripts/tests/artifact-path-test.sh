#!/usr/bin/env bash
# artifact-path-test.sh
# Minimal tests for compute-artifact-path.sh and validate-artifact-path.sh

set -euo pipefail

readonly REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
readonly COMPUTE="${REPO_ROOT}/scripts/compute-artifact-path.sh"
readonly VALIDATE="${REPO_ROOT}/scripts/validate-artifact-path.sh"

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

# Case 1: single-loader compute.
mkdir -p "${tmp_dir}/single"
cat >"${tmp_dir}/single/gradle.properties" <<'EOF'
minecraft_version=1.21.1
mod_id=examplemod
mod_version=0.1.0
loader_multi=false
loader_type=forge
EOF

out="$(${COMPUTE} --project-root "${tmp_dir}/single")"
assert_contains "$out" "artifact_path=build/libs/examplemod-1.21.1-0.1.0.jar"

# validate should fail before artifact exists.
assert_exit_code 1 "${VALIDATE}" --project-root "${tmp_dir}/single"

# create artifact and validate should pass.
mkdir -p "${tmp_dir}/single/build/libs"
: >"${tmp_dir}/single/build/libs/examplemod-1.21.1-0.1.0.jar"
assert_exit_code 0 "${VALIDATE}" --project-root "${tmp_dir}/single"

# Case 2: multi-loader requires --loader.
mkdir -p "${tmp_dir}/multi/forge" "${tmp_dir}/multi/fabric"
: >"${tmp_dir}/multi/forge/build.gradle"
: >"${tmp_dir}/multi/fabric/build.gradle"
cat >"${tmp_dir}/multi/gradle.properties" <<'EOF'
minecraft_version=1.21.1
mod_id=examplemod
mod_version=0.1.0
loader_multi=true
active_loaders=forge,fabric
EOF

assert_exit_code 1 "${COMPUTE}" --project-root "${tmp_dir}/multi"
out2="$(${COMPUTE} --project-root "${tmp_dir}/multi" --loader forge)"
assert_contains "$out2" "artifact_path=forge/build/libs/examplemod-forge-1.21.1-0.1.0.jar"

# validate should fail until artifact exists.
assert_exit_code 1 "${VALIDATE}" --project-root "${tmp_dir}/multi" --loader forge
mkdir -p "${tmp_dir}/multi/forge/build/libs"
: >"${tmp_dir}/multi/forge/build/libs/examplemod-forge-1.21.1-0.1.0.jar"
assert_exit_code 0 "${VALIDATE}" --project-root "${tmp_dir}/multi" --loader forge

echo "OK"
