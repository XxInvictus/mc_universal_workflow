#!/usr/bin/env bash
# migration-helpers-test.sh
# Minimal tests for scripts/migration/* helpers.

set -euo pipefail

readonly REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
readonly SCAN_SCRIPT="${REPO_ROOT}/scripts/migration/scan-legacy-gradle-properties.sh"
readonly MIGRATE_SCRIPT="${REPO_ROOT}/scripts/migration/migrate-legacy-gradle-properties.sh"

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

assert_file_contains() {
  local file="$1"
  local needle="$2"
  grep -Fq "$needle" "$file" || fail "expected file to contain: ${needle}"
}

tmp_dir=""
cleanup() {
  if [[ -n "${tmp_dir:-}" && -d "$tmp_dir" ]]; then
    rm -rf "$tmp_dir"
  fi
}
trap cleanup EXIT

tmp_dir="$(mktemp -d)"

# Case 1: scan should report missing canonical keys and aliases.
props1="${tmp_dir}/gradle.properties"
cat >"$props1" <<'EOF'
mc_version=1.21.1
modid=examplemod
loader_multi=false
loader_type=forge
EOF

scan_out="$($SCAN_SCRIPT --file "$props1")"
assert_contains "$scan_out" "missing_canonical_keys=minecraft_version,mod_id,mod_version"
assert_contains "$scan_out" "mc_version -> minecraft_version"
assert_contains "$scan_out" "modid -> mod_id"

# Case 2: migrate (dry-run) should rewrite aliases into canonical keys.
migrated="$($MIGRATE_SCRIPT --file "$props1")"
assert_contains "$migrated" "minecraft_version=1.21.1"
assert_contains "$migrated" "mod_id=examplemod"

# Case 3: migrate --write updates the file and creates a backup.
props2="${tmp_dir}/gradle2.properties"
cat >"$props2" <<'EOF'
  minecraftVersion = 1.21.1
  modId=examplemod
  modVersion = 0.1.0
  loader_multi=false
  loader_type=forge
EOF

$MIGRATE_SCRIPT --file "$props2" --write --backup-suffix ".bak"
[[ -f "${props2}.bak" ]] || fail "expected backup file to exist"
assert_file_contains "$props2" "minecraft_version = 1.21.1"
assert_file_contains "$props2" "mod_id=examplemod"
assert_file_contains "$props2" "mod_version = 0.1.0"

echo "OK"
