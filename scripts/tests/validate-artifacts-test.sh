#!/usr/bin/env bash

set -euo pipefail

fail() {
  echo "FAIL: $1" >&2
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

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

require_cmd() {
  command -v "$1" >/dev/null 2>&1
}

if ! require_cmd zip || ! require_cmd unzip; then
  echo "SKIP: zip/unzip not available"
  exit 0
fi

workdir="$(mktemp -d)"
cleanup() {
  rm -rf "$workdir"
}
trap cleanup EXIT

# --- Forge fixture (pass) ---
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

(
  cd "$workdir/forge"
  zip -q "build/libs/examplemod-forge-1.21.1-0.1.0.jar" "META-INF/MANIFEST.MF" "META-INF/mods.toml"
)

assert_ok "forge jar validates" bash "$SCRIPT_DIR/validate-artifacts.sh" --project-root "$workdir/forge"

# --- Forge fixture missing metadata (fail) ---
mkdir -p "$workdir/forge-bad/build/libs" "$workdir/forge-bad/META-INF"
cat > "$workdir/forge-bad/gradle.properties" <<'EOF'
minecraft_version=1.21.1
mod_id=examplemod
mod_version=0.1.0
java_version=21
loader_multi=false
loader_type=forge
EOF

cat > "$workdir/forge-bad/META-INF/MANIFEST.MF" <<'EOF'
Manifest-Version: 1.0
EOF

(
  cd "$workdir/forge-bad"
  zip -q "build/libs/examplemod-forge-1.21.1-0.1.0.jar" "META-INF/MANIFEST.MF"
)

assert_fail "forge jar missing mods.toml fails" bash "$SCRIPT_DIR/validate-artifacts.sh" --project-root "$workdir/forge-bad"

# --- NeoForge fixture (pass) ---
mkdir -p "$workdir/neoforge/build/libs" "$workdir/neoforge/META-INF"
cat > "$workdir/neoforge/gradle.properties" <<'EOF'
minecraft_version=1.21.1
mod_id=examplemod
mod_version=0.1.0
java_version=21
loader_multi=false
loader_type=neoforge
EOF

cat > "$workdir/neoforge/META-INF/MANIFEST.MF" <<'EOF'
Manifest-Version: 1.0
EOF

cat > "$workdir/neoforge/META-INF/neoforge.mods.toml" <<'EOF'
modLoader="javafml"
loaderVersion="[1,)"
license="MIT"
[[mods]]
modId="examplemod"
version="0.1.0"
EOF

(
  cd "$workdir/neoforge"
  zip -q "build/libs/examplemod-neoforge-1.21.1-0.1.0.jar" "META-INF/MANIFEST.MF" "META-INF/neoforge.mods.toml"
)

assert_ok "neoforge jar validates" bash "$SCRIPT_DIR/validate-artifacts.sh" --project-root "$workdir/neoforge"

# --- Fabric fixture (pass) ---
mkdir -p "$workdir/fabric/build/libs"
cat > "$workdir/fabric/gradle.properties" <<'EOF'
minecraft_version=1.21.1
mod_id=examplemod
mod_version=0.1.0
java_version=21
loader_multi=false
loader_type=fabric
EOF

cat > "$workdir/fabric/fabric.mod.json" <<'EOF'
{
  "schemaVersion": 1,
  "id": "examplemod",
  "version": "0.1.0",
  "name": "Example Mod"
}
EOF

mkdir -p "$workdir/fabric/META-INF"
cat > "$workdir/fabric/META-INF/MANIFEST.MF" <<'EOF'
Manifest-Version: 1.0
EOF

(
  cd "$workdir/fabric"
  zip -q "build/libs/examplemod-fabric-1.21.1-0.1.0.jar" "META-INF/MANIFEST.MF" "fabric.mod.json"
)

assert_ok "fabric jar validates" bash "$SCRIPT_DIR/validate-artifacts.sh" --project-root "$workdir/fabric"

echo "OK"
