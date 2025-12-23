#!/bin/bash

# Validates that Mojang's version manifest contains a known Minecraft version id.
#
# Purpose:
# - Prevent regressions in our minecraft-version validation logic.
# - Provide a clear CI failure if Mojang manifest parsing breaks.

set -euo pipefail

readonly MANIFEST_URL="https://launchermeta.mojang.com/mc/game/version_manifest_v2.json"
readonly KNOWN_GOOD_VERSION="1.21.1"
readonly KNOWN_BAD_VERSION="0.0.0-not-a-version"

require_cmd() {
  local cmd="$1"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "ERROR: required command '$cmd' is not installed." >&2
    exit 1
  fi
}

main() {
  require_cmd curl
  require_cmd jq

  # Positive check: known good version must exist.
  if ! curl -fsSL "$MANIFEST_URL" | jq -e --arg mc "$KNOWN_GOOD_VERSION" '.versions | any(.id == $mc)' >/dev/null; then
    echo "ERROR: Expected minecraft version '$KNOWN_GOOD_VERSION' not found in Mojang version manifest." >&2
    exit 1
  fi

  # Negative check: known bad version must not exist.
  if curl -fsSL "$MANIFEST_URL" | jq -e --arg mc "$KNOWN_BAD_VERSION" '.versions | any(.id == $mc)' >/dev/null; then
    echo "ERROR: Unexpected minecraft version '$KNOWN_BAD_VERSION' found in Mojang version manifest." >&2
    exit 1
  fi

  echo "OK"
}

main "$@"
