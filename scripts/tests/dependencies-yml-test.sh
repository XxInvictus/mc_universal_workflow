#!/usr/bin/env bash
# dependencies-yml-test.sh
# Tests for scripts/validate-dependencies-yml.sh

set -euo pipefail

readonly REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
readonly VALIDATE="${REPO_ROOT}/scripts/validate-dependencies-yml.sh"

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

if ! command -v yq >/dev/null 2>&1; then
  echo "SKIP: yq not installed"
  exit 0
fi

tmp_dir=""
cleanup() {
  if [[ -n "${tmp_dir:-}" && -d "$tmp_dir" ]]; then
    rm -rf "$tmp_dir"
  fi
}
trap cleanup EXIT

tmp_dir="$(mktemp -d)"

# Case 1: missing deps file should succeed.
mkdir -p "${tmp_dir}/missing"
out1="$(${VALIDATE} --project-root "${tmp_dir}/missing")"
assert_contains "$out1" "dependencies_present=false"

# Case 2: minimal valid deps file.
mkdir -p "${tmp_dir}/valid"
cat >"${tmp_dir}/valid/dependencies.yml" <<'EOF'
version: "1.0"
settings:
  auto_resolve_latest: false

dependencies:
  runtime:
    - name: pmmo
      identifiers:
        modrinth_id: KFQYC1Uy
      version:
        default: "2.7.35"
      source:
        type: modrinth
EOF
out2="$(${VALIDATE} --project-root "${tmp_dir}/valid")"
assert_contains "$out2" "dependencies_present=true"
assert_contains "$out2" "dependencies_schema_version=1.0"
assert_contains "$out2" "dependencies_runtime_count=1"

# Case 3: reject auto_resolve_latest.
mkdir -p "${tmp_dir}/bad_auto_latest"
cat >"${tmp_dir}/bad_auto_latest/dependencies.yml" <<'EOF'
version: "1.0"
settings:
  auto_resolve_latest: true

dependencies:
  runtime: []
EOF
assert_exit_code 1 "${VALIDATE}" --project-root "${tmp_dir}/bad_auto_latest"

# Case 4: reject version.latest
mkdir -p "${tmp_dir}/bad_latest"
cat >"${tmp_dir}/bad_latest/dependencies.yml" <<'EOF'
version: "1.0"
dependencies:
  runtime:
    - name: something
      identifiers:
        modrinth_id: abc
      version:
        latest: true
      source:
        type: modrinth
EOF
assert_exit_code 1 "${VALIDATE}" --project-root "${tmp_dir}/bad_latest"

echo "OK"
