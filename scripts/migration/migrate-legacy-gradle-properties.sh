#!/usr/bin/env bash
# migrate-legacy-gradle-properties.sh
# Out-of-band helper: rename a small set of common legacy gradle.properties keys
# to this repo's canonical keys.
#
# This script is intentionally NOT invoked by any workflow/action in this repo.

set -euo pipefail

readonly SCRIPT_NAME="$(basename "$0")"

usage() {
  cat <<'EOF'
Usage:
  migrate-legacy-gradle-properties.sh --file <path> [--write]
                                    [--backup-suffix <suffix>] [--overwrite-backup]

Renames a conservative set of legacy keys when the canonical key is missing:
  - mc_version, minecraftVersion -> minecraft_version
  - modid, modId                 -> mod_id
  - modVersion                   -> mod_version

Default behavior is dry-run: prints the rewritten file to stdout.
Use --write to update the file in place (creates a backup).

Notes:
  - This is a migration helper only; it is not used by CI/workflows.
  - It intentionally avoids guessing ambiguous keys like 'version'.
EOF
}

fail() {
  local message="$1"
  echo "ERROR: ${message}" >&2
  exit 1
}

file_path=""
write_in_place="false"
backup_suffix=".bak"
overwrite_backup="false"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --file)
      file_path="${2:-}"
      [[ -n "$file_path" ]] || fail "--file requires a value"
      shift 2
      ;;
    --write)
      write_in_place="true"
      shift
      ;;
    --backup-suffix)
      backup_suffix="${2:-}"
      [[ -n "$backup_suffix" ]] || fail "--backup-suffix requires a value"
      shift 2
      ;;
    --overwrite-backup)
      overwrite_backup="true"
      shift
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

# Collect keys to decide whether canonical keys already exist.
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

map_key() {
  local key="$1"

  # Only rename if canonical key is missing.
  if ! has_key "minecraft_version"; then
    case "$key" in
      mc_version|minecraftVersion)
        echo "minecraft_version"
        return 0
        ;;
    esac
  fi

  if ! has_key "mod_id"; then
    case "$key" in
      modid|modId)
        echo "mod_id"
        return 0
        ;;
    esac
  fi

  if ! has_key "mod_version"; then
    case "$key" in
      modVersion)
        echo "mod_version"
        return 0
        ;;
    esac
  fi

  echo "$key"
}

rewrite() {
  while IFS= read -r line || [[ -n "$line" ]]; do
    if [[ "$line" =~ ^([[:space:]]*)([A-Za-z0-9_.-]+)([[:space:]]*=[[:space:]]*)(.*)$ ]]; then
      prefix="${BASH_REMATCH[1]}"
      key="${BASH_REMATCH[2]}"
      sep="${BASH_REMATCH[3]}"
      rest="${BASH_REMATCH[4]}"

      new_key="$(map_key "$key")"
      echo "${prefix}${new_key}${sep}${rest}"
    else
      echo "$line"
    fi
  done <"$file_path"
}

if [[ "$write_in_place" == "true" ]]; then
  backup_path="${file_path}${backup_suffix}"
  if [[ -e "$backup_path" && "$overwrite_backup" != "true" ]]; then
    fail "Backup already exists: ${backup_path} (use --overwrite-backup to replace)"
  fi

  cp -f "$file_path" "$backup_path"

  tmp_out=""
  tmp_out="$(mktemp)"
  rewrite >"$tmp_out"
  mv -f "$tmp_out" "$file_path"

  echo "OK: updated ${file_path} (backup: ${backup_path})" >&2
else
  rewrite
fi
