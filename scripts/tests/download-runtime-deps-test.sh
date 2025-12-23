#!/usr/bin/env bash
# download-runtime-deps-test.sh
# Minimal offline tests for scripts/download-runtime-deps.sh using source.type=url.

set -euo pipefail

readonly REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
readonly SCRIPT_UNDER_TEST="${REPO_ROOT}/scripts/download-runtime-deps.sh"

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

if ! command -v yq >/dev/null 2>&1; then
  echo "SKIP: yq not installed"
  exit 0
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "SKIP: jq not installed"
  exit 0
fi

if ! command -v curl >/dev/null 2>&1; then
  echo "SKIP: curl not installed"
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

mkdir -p "${tmp_dir}/project"
mkdir -p "${tmp_dir}/out"

# Create a local "mod jar" to download using file://
printf 'not-a-real-jar-but-non-empty\n' >"${tmp_dir}/dep-a.jar"

dep_url="file://${tmp_dir}/dep-a.jar"

cat >"${tmp_dir}/project/dependencies.yml" <<EOF
version: "1.0"
settings:
  auto_resolve_latest: false

dependencies:
  runtime:
    - name: dep-a
      loaders: [forge]
      minecraft: ["1.21.1"]
      source:
        type: url
        url: "${dep_url}"
    - name: dep-b
      loaders: [fabric]
      minecraft: ["1.21.1"]
      source:
        type: url
        url: "${dep_url}"
EOF

out="$(${SCRIPT_UNDER_TEST} --project-root "${tmp_dir}/project" --loader forge --minecraft-version 1.21.1 --dest-dir "${tmp_dir}/out")"

assert_contains "$out" "dependencies_present=true"
assert_contains "$out" "downloaded_count=1"

# Should have downloaded dep-a.jar only
[[ -f "${tmp_dir}/out/dep-a.jar" ]] || fail "expected dep-a.jar in dest dir"

echo "OK"
