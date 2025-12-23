#!/usr/bin/env bash

set -euo pipefail

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

assert_ok() {
  local label="$1"
  shift
  set +e
  local out
  out="$("$@" 2>&1)"
  local code="$?"
  set -e

  if [[ "$code" != "0" ]]; then
    echo "--- command failed (expected success): ${label} ---" >&2
    echo "Command: $*" >&2
    echo "$out" >&2
    fail "expected success: ${label}"
  fi
}

assert_fail() {
  local label="$1"
  shift
  set +e
  local out
  out="$("$@" 2>&1)"
  local code="$?"
  set -e

  if [[ "$code" == "0" ]]; then
    echo "--- command succeeded (expected failure): ${label} ---" >&2
    echo "Command: $*" >&2
    echo "$out" >&2
    fail "expected failure: ${label}"
  fi
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1
}

# These tests generate fixture jars with marker strings. They validate the script's
# heuristic detection works (not full bytecode correctness).
if ! require_cmd zip || ! require_cmd unzip || ! require_cmd strings; then
  echo "SKIP: zip/unzip/strings not available"
  exit 0
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

workdir="$(mktemp -d)"
cleanup() {
  rm -rf "$workdir"
}
trap cleanup EXIT

make_jar_with_markers() {
  local root="$1"
  local jar_rel="$2"
  shift 2

  mkdir -p "${root}/build/libs"
  # Put marker strings in plain text files so strings(1) will reliably detect them.
  local i=0
  for marker in "$@"; do
    i=$((i + 1))
    printf '%s\n' "$marker" > "${root}/marker-${i}.txt"
  done

  (
    cd "$root"
    zip -q "$jar_rel" marker-*.txt
  )
}

# Forge accepts SRG or Mojmap (Forge toolchains vary)
mkdir -p "$workdir/forge"
cat > "$workdir/forge/gradle.properties" <<'EOF'
minecraft_version=1.21.1
mod_id=examplemod
mod_version=0.1.0
java_version=21
loader_multi=false
loader_type=forge
EOF

# Push counts above threshold by repeating patterns.
srg_markers=()
for _ in $(seq 1 40); do
  srg_markers+=("func_1234_a" "field_5678_b")
done
make_jar_with_markers "$workdir/forge" "build/libs/examplemod-forge-1.21.1-0.1.0.jar" "${srg_markers[@]}"

assert_ok "forge srg validates" bash "$SCRIPT_DIR/validate-mappings.sh" --project-root "$workdir/forge"

# Forge should also validate if jar looks Mojmap
mkdir -p "$workdir/forge-moj"
cat > "$workdir/forge-moj/gradle.properties" <<'EOF'
minecraft_version=1.21.1
mod_id=examplemod
mod_version=0.1.0
java_version=21
loader_multi=false
loader_type=forge
EOF

moj_markers_forge=()
for _ in $(seq 1 25); do
  moj_markers_forge+=("net/minecraft/world/entity/Entity" "net/minecraft/client/Minecraft")
done
make_jar_with_markers "$workdir/forge-moj" "build/libs/examplemod-forge-1.21.1-0.1.0.jar" "${moj_markers_forge[@]}"

assert_ok "forge mojmap validates" bash "$SCRIPT_DIR/validate-mappings.sh" --project-root "$workdir/forge-moj"

# Fabric expects intermediary
mkdir -p "$workdir/fabric"
cat > "$workdir/fabric/gradle.properties" <<'EOF'
minecraft_version=1.21.1
mod_id=examplemod
mod_version=0.1.0
java_version=21
loader_multi=false
loader_type=fabric
EOF

inter_markers=()
for _ in $(seq 1 40); do
  inter_markers+=("class_1234" "method_5678")
done
make_jar_with_markers "$workdir/fabric" "build/libs/examplemod-fabric-1.21.1-0.1.0.jar" "${inter_markers[@]}"

assert_ok "fabric intermediary validates" bash "$SCRIPT_DIR/validate-mappings.sh" --project-root "$workdir/fabric"

# Fabric: minimal/example mods may not reference net/minecraft at all.
# In that case, the heuristic cannot infer mapping namespace from the artifact,
# and validation should not hard-fail.
mkdir -p "$workdir/fabric-unknown"
cat > "$workdir/fabric-unknown/gradle.properties" <<'EOF'
minecraft_version=1.21.1
mod_id=examplemod
mod_version=0.1.0
java_version=21
loader_multi=false
loader_type=fabric
EOF

make_jar_with_markers "$workdir/fabric-unknown" "build/libs/examplemod-fabric-1.21.1-0.1.0.jar" "hello-world"

assert_ok "fabric unknown mapping allowed" bash "$SCRIPT_DIR/validate-mappings.sh" --project-root "$workdir/fabric-unknown"

# NeoForge expects mojmap (net/minecraft paths) and should fail if intermediary markers dominate
mkdir -p "$workdir/neoforge"
cat > "$workdir/neoforge/gradle.properties" <<'EOF'
minecraft_version=1.21.1
mod_id=examplemod
mod_version=0.1.0
java_version=21
loader_multi=false
loader_type=neoforge
EOF

moj_markers=()
for _ in $(seq 1 25); do
  moj_markers+=("net/minecraft/world/entity/Entity" "net/minecraft/client/Minecraft")
done
make_jar_with_markers "$workdir/neoforge" "build/libs/examplemod-neoforge-1.21.1-0.1.0.jar" "${moj_markers[@]}"

assert_ok "neoforge mojmap validates" bash "$SCRIPT_DIR/validate-mappings.sh" --project-root "$workdir/neoforge"

# Negative: Forge should fail if jar looks intermediary
mkdir -p "$workdir/forge-bad"
cat > "$workdir/forge-bad/gradle.properties" <<'EOF'
minecraft_version=1.21.1
mod_id=examplemod
mod_version=0.1.0
java_version=21
loader_multi=false
loader_type=forge
EOF

make_jar_with_markers "$workdir/forge-bad" "build/libs/examplemod-forge-1.21.1-0.1.0.jar" "${inter_markers[@]}"

assert_fail "forge rejects intermediary" bash "$SCRIPT_DIR/validate-mappings.sh" --project-root "$workdir/forge-bad"

echo "OK"
