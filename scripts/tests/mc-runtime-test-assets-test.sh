#!/bin/bash

# Validates that the pinned headlesshq/mc-runtime-test release contains
# the expected runtime test jar asset naming pattern for a known Minecraft version.
#
# Purpose:
# - Prevent regressions in our GitHub release asset existence check.
# - Avoid brittle grep/pipefail behavior by using jq.

set -euo pipefail

readonly REPO="headlesshq/mc-runtime-test"
readonly TAG="4.1.0"
readonly MC="1.21.10"
readonly MCRT="fabric"

require_cmd() {
  local cmd="$1"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "ERROR: required command '$cmd' is not installed." >&2
    exit 1
  fi
}

auth_header_args() {
  # Prefer GH_TOKEN, then GITHUB_TOKEN; allow unauthenticated requests as fallback.
  local token="${GH_TOKEN:-${GITHUB_TOKEN:-}}"
  if [[ -n "$token" ]]; then
    printf '%s\n' "-H" "Authorization: Bearer ${token}"
  fi
}

main() {
  require_cmd curl
  require_cmd jq

  local api_url="https://api.github.com/repos/${REPO}/releases/tags/${TAG}"

  local -a headers
  mapfile -t headers < <(auth_header_args)

  local json
  json="$(curl -fsSL \
    -H "Accept: application/vnd.github+json" \
    "${headers[@]}" \
    "$api_url")"

  local asset_re
  asset_re="^mc-runtime-test-${MC}-.*-${MCRT}-release\\.jar$"

  if ! jq -e --arg re "$asset_re" '.assets | map(.name) | any(test($re))' <<<"$json" >/dev/null; then
    echo "ERROR: ${REPO}@${TAG} has no asset matching mc-runtime-test-${MC}-*-${MCRT}-release.jar" >&2
    exit 1
  fi

  # Negative check: this should never exist.
  if jq -e --arg re "^mc-runtime-test-0\\.0\\.0-not-a-version-.*-${MCRT}-release\\.jar$" '.assets | map(.name) | any(test($re))' <<<"$json" >/dev/null; then
    echo "ERROR: Unexpected asset match for clearly invalid MC version." >&2
    exit 1
  fi

  echo "OK"
}

main "$@"
