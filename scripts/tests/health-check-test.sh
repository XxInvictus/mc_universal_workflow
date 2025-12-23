#!/usr/bin/env bash
# health-check-test.sh
# Minimal tests for scripts/health-check.sh

set -euo pipefail

fail() {
  local message="$1"
  echo "FAIL: ${message}" >&2
  exit 1
}

assert_ok() {
  local label="$1"
  shift
  if ! "$@" >/dev/null 2>&1; then
    fail "expected success: ${label}"
  fi
}

assert_fail() {
  local label="$1"
  shift
  if "$@" >/dev/null 2>&1; then
    fail "expected failure: ${label}"
  fi
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1
}

if ! require_cmd zip || ! require_cmd unzip || ! require_cmd strings; then
  echo "SKIP: zip/unzip/strings not available"
  exit 0
fi

readonly REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
readonly HEALTH_CHECK="${REPO_ROOT}/scripts/health-check.sh"

workdir="$(mktemp -d)"
cleanup() {
  rm -rf "$workdir"
}
trap cleanup EXIT

# Forge single-loader (pass)
mkdir -p "$workdir/forge/build/libs" "$workdir/forge/META-INF"
cat > "$workdir/forge/gradle.properties" <<'EOF'
minecraft_version=1.21.1
mod_id=examplemod
mod_version=0.1.0
java_version=21
loader_multi=false
loader_type=forge
EOF

cat > "$workdir/forge/META-INF/MANIFEST.MF" <<'EOF'
Manifest-Version: 1.0
EOF

cat > "$workdir/forge/META-INF/mods.toml" <<'EOF'
modLoader="javafml"
loaderVersion="[1,)"
license="MIT"
[[mods]]
modId="examplemod"
version="0.1.0"
EOF

mkdir -p "$workdir/forge/markers"
for i in $(seq 1 40); do
  echo "func_1234_a" >> "$workdir/forge/markers/srg.txt"
  echo "field_5678_b" >> "$workdir/forge/markers/srg.txt"
done

(
  cd "$workdir/forge"
  zip -q "build/libs/examplemod-forge-1.21.1-0.1.0.jar" META-INF/MANIFEST.MF META-INF/mods.toml markers/srg.txt
)

assert_ok "health-check forge passes" bash "$HEALTH_CHECK" --project-root "$workdir/forge"

# Missing artifact should fail
mkdir -p "$workdir/missing"
cat > "$workdir/missing/gradle.properties" <<'EOF'
minecraft_version=1.21.1
mod_id=examplemod
mod_version=0.1.0
java_version=21
loader_multi=false
loader_type=forge
EOF

assert_fail "health-check fails without artifact" bash "$HEALTH_CHECK" --project-root "$workdir/missing"

# Multi-loader (forge+fabric) should validate both
mkdir -p "$workdir/multi/forge" "$workdir/multi/fabric"
: > "$workdir/multi/forge/build.gradle"
: > "$workdir/multi/fabric/build.gradle"
cat > "$workdir/multi/gradle.properties" <<'EOF'
minecraft_version=1.21.1
mod_id=examplemod
mod_version=0.1.0
java_version=21
loader_multi=true
active_loaders=forge,fabric
EOF

mkdir -p "$workdir/multi/forge/build/libs" "$workdir/multi/forge/META-INF" "$workdir/multi/forge/markers"
cat > "$workdir/multi/forge/META-INF/MANIFEST.MF" <<'EOF'
Manifest-Version: 1.0
EOF
cat > "$workdir/multi/forge/META-INF/mods.toml" <<'EOF'
modLoader="javafml"
loaderVersion="[1,)"
license="MIT"
[[mods]]
modId="examplemod"
version="0.1.0"
EOF
for i in $(seq 1 40); do
  echo "func_1234_a" >> "$workdir/multi/forge/markers/srg.txt"
  echo "field_5678_b" >> "$workdir/multi/forge/markers/srg.txt"
done
(
  cd "$workdir/multi/forge"
  zip -q "build/libs/examplemod-forge-1.21.1-0.1.0.jar" META-INF/MANIFEST.MF META-INF/mods.toml markers/srg.txt
)

mkdir -p "$workdir/multi/fabric/build/libs" "$workdir/multi/fabric/META-INF" "$workdir/multi/fabric/markers"
cat > "$workdir/multi/fabric/META-INF/MANIFEST.MF" <<'EOF'
Manifest-Version: 1.0
EOF
cat > "$workdir/multi/fabric/fabric.mod.json" <<'EOF'
{"schemaVersion":1,"id":"examplemod","version":"0.1.0","name":"Example Mod"}
EOF
for i in $(seq 1 40); do
  echo "class_1234" >> "$workdir/multi/fabric/markers/inter.txt"
  echo "method_5678" >> "$workdir/multi/fabric/markers/inter.txt"
done
(
  cd "$workdir/multi/fabric"
  zip -q "build/libs/examplemod-fabric-1.21.1-0.1.0.jar" META-INF/MANIFEST.MF fabric.mod.json markers/inter.txt
)

assert_ok "health-check multi passes" bash "$HEALTH_CHECK" --project-root "$workdir/multi"

echo "OK"
