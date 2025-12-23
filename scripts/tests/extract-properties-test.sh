#!/usr/bin/env bash
# extract-properties-test.sh
# Minimal tests for scripts/extract-properties.sh

set -euo pipefail

readonly REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
readonly SCRIPT_UNDER_TEST="${REPO_ROOT}/scripts/extract-properties.sh"

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

require_cmd() {
  command -v "$1" >/dev/null 2>&1
}

tmp_dir=""
cleanup() {
  if [[ -n "${tmp_dir:-}" && -d "$tmp_dir" ]]; then
    rm -rf "$tmp_dir"
  fi
}
trap cleanup EXIT

tmp_dir="$(mktemp -d)"

mkdir -p "${tmp_dir}/proj"
cat >"${tmp_dir}/proj/gradle.properties" <<'EOF'
minecraft_version=1.21.1
mod_id=examplemod
mod_version=0.1.0
java_version=21
loader_multi=false
loader_type=forge

# extra keys (preset=all should include)
custom_key=hello
another_key = world
EOF

# Canonical preset (env)
out1="$(${SCRIPT_UNDER_TEST} --project-root "${tmp_dir}/proj" --preset canonical --format env)"
assert_contains "$out1" "minecraft_version=1.21.1"
assert_contains "$out1" "active_loaders=forge"

# All preset (env)
out2="$(${SCRIPT_UNDER_TEST} --project-root "${tmp_dir}/proj" --preset all --format env)"
assert_contains "$out2" "custom_key=hello"
assert_contains "$out2" "another_key=world"

# JSON output (requires jq)
if require_cmd jq; then
  out3="$(${SCRIPT_UNDER_TEST} --project-root "${tmp_dir}/proj" --preset canonical --format json)"
  assert_contains "$out3" '"minecraft_version"'
  assert_contains "$out3" '"1.21.1"'
fi

# YAML output (requires yq)
if require_cmd yq && require_cmd jq; then
  out4="$(${SCRIPT_UNDER_TEST} --project-root "${tmp_dir}/proj" --preset canonical --format yaml)"
  assert_contains "$out4" "minecraft_version: 1.21.1"
fi

# Invalid line should fail for preset=all
mkdir -p "${tmp_dir}/bad"
cat >"${tmp_dir}/bad/gradle.properties" <<'EOF'
minecraft_version=1.21.1
this_is_not_valid
EOF

assert_exit_code 1 "${SCRIPT_UNDER_TEST}" --project-root "${tmp_dir}/bad" --preset all --format env

echo "OK"
