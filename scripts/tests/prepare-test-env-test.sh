#!/usr/bin/env bash
# prepare-test-env-test.sh
# Minimal tests for scripts/prepare-test-env.sh

set -euo pipefail

readonly REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
readonly SCRIPT_UNDER_TEST="${REPO_ROOT}/scripts/prepare-test-env.sh"

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

# Case 1: single-loader with resolved artifact.
mkdir -p "${tmp_dir}/single/build/libs"
cat >"${tmp_dir}/single/gradle.properties" <<'EOF'
minecraft_version=1.21.1
mod_id=examplemod
mod_version=0.1.0
java_version=21
loader_multi=false
loader_type=forge
EOF
: >"${tmp_dir}/single/build/libs/examplemod-1.21.1-0.1.0.jar"

pushd "$tmp_dir" >/dev/null
out1="$(${SCRIPT_UNDER_TEST} --project-root "${tmp_dir}/single")"
popd >/dev/null

assert_contains "$out1" "loader_type=forge"
assert_contains "$out1" "artifact_path=build/libs/examplemod-1.21.1-0.1.0.jar"
assert_contains "$out1" "mod_dir=run/mods"

# Should have staged the artifact into ./run/mods relative to PWD ($tmp_dir).
[[ -f "${tmp_dir}/run/mods/examplemod-1.21.1-0.1.0.jar" ]] || fail "expected staged jar in run/mods"

# Case 2: multi-loader requires --loader.
mkdir -p "${tmp_dir}/multi/forge/build.gradle" "${tmp_dir}/multi/fabric/build.gradle"
cat >"${tmp_dir}/multi/gradle.properties" <<'EOF'
minecraft_version=1.21.1
mod_id=examplemod
mod_version=0.1.0
java_version=21
loader_multi=true
active_loaders=forge,fabric
EOF
assert_exit_code 1 "${SCRIPT_UNDER_TEST}" --project-root "${tmp_dir}/multi"

# Provide loader and artifact.
mkdir -p "${tmp_dir}/multi/forge/build/libs"
: >"${tmp_dir}/multi/forge/build/libs/examplemod-forge-1.21.1-0.1.0.jar"

pushd "$tmp_dir" >/dev/null
out2="$(${SCRIPT_UNDER_TEST} --project-root "${tmp_dir}/multi" --loader forge)"
popd >/dev/null

assert_contains "$out2" "loader_type=forge"
assert_contains "$out2" "artifact_path=forge/build/libs/examplemod-forge-1.21.1-0.1.0.jar"

[[ -f "${tmp_dir}/run/mods/examplemod-forge-1.21.1-0.1.0.jar" ]] || fail "expected staged multi-loader jar in run/mods"

echo "OK"
