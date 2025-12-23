#!/usr/bin/env bash
# scan-legacy-gradle-properties.sh
# Out-of-band helper: scan a gradle.properties file for canonical key presence
# and flag common legacy aliases that may need renaming.
#
# This script is intentionally NOT invoked by any workflow/action in this repo.

set -euo pipefail

readonly SCRIPT_NAME="$(basename "$0")"

usage() {
  cat <<'EOF'
Usage:
  scan-legacy-gradle-properties.sh --file <path>

Scans a gradle.properties file and reports:
  - Missing canonical keys required by this repo
  - Detected common legacy aliases that could be renamed

Notes:
  - This is a migration helper only; it does not change files.
EOF
}

fail() {
  local message="$1"
  echo "ERROR: ${message}" >&2
  exit 1
}

file_path=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --file)
      file_path="${2:-}"
      [[ -n "$file_path" ]] || fail "--file requires a value"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      fail "Unknown argument: $1"
      ;;
  esac
done

[[ -n "$file_path" ]] || fail "--file is required"
[[ -f "$file_path" ]] || fail "File not found: ${file_path}"

# Parse keys from gradle.properties (simple key=value lines; ignores comments).
keys_csv=""
while IFS= read -r line || [[ -n "$line" ]]; do
  [[ -n "${line//[[:space:]]/}" ]] || continue
  [[ "$line" =~ ^[[:space:]]*[#!] ]] && continue

  if [[ "$line" =~ ^([[:space:]]*)([A-Za-z0-9_.-]+)([[:space:]]*=[[:space:]]*).*$ ]]; then
    key="${BASH_REMATCH[2]}"
    keys_csv+="${key},"
  fi
done <"$file_path"

has_key() {
  local key="$1"
  [[ ",${keys_csv}," == *",${key},"* ]]
}

# Canonical keys required by this repo.
missing=()
for k in minecraft_version mod_id mod_version loader_multi; do
  if ! has_key "$k"; then
    missing+=("$k")
  fi
done

# Loader-specific canonical keys.
if has_key "loader_multi"; then
  loader_multi_value=""
  loader_multi_value="$(grep -E '^[[:space:]]*loader_multi[[:space:]]*=' "$file_path" | head -n 1 | sed -E 's/^[^=]*=//; s/^[[:space:]]+//; s/[[:space:]]+$//' || true)"

  if [[ "$loader_multi_value" == "true" ]]; then
    if ! has_key "active_loaders"; then
      missing+=("active_loaders")
    fi
  elif [[ "$loader_multi_value" == "false" ]]; then
    if ! has_key "loader_type"; then
      missing+=("loader_type")
    fi
  fi
fi

# Common aliases we can safely *suggest* renaming.
# We keep this list intentionally small to avoid wrong guesses.
alias_hits=()
if ! has_key "minecraft_version"; then
  for a in mc_version minecraftVersion; do
    if has_key "$a"; then
      alias_hits+=("${a} -> minecraft_version")
    fi
  done
fi

if ! has_key "mod_id"; then
  for a in modid modId; do
    if has_key "$a"; then
      alias_hits+=("${a} -> mod_id")
    fi
  done
fi

if ! has_key "mod_version"; then
  for a in modVersion; do
    if has_key "$a"; then
      alias_hits+=("${a} -> mod_version")
    fi
  done
fi

echo "file=${file_path}"

if [[ ${#missing[@]} -eq 0 ]]; then
  echo "missing_canonical_keys="
else
  (IFS=,; echo "missing_canonical_keys=${missing[*]}")
fi

if [[ ${#alias_hits[@]} -eq 0 ]]; then
  echo "detected_aliases="
else
  (IFS=$'\n'; echo "detected_aliases=${alias_hits[*]}")
fi
