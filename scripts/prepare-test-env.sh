#!/usr/bin/env bash
# prepare-test-env.sh
# Prepares the workspace for headlesshq/mc-runtime-test by staging the built mod jar
# (and optional additional mods) into ./run/mods.

set -euo pipefail

usage() {
  cat <<'EOF'
Usage: prepare-test-env.sh [OPTIONS]

Options:
  --project-root <path>       Project root containing gradle.properties (default: .)
  --loader <forge|neoforge|fabric>
                              Loader to prepare (required for multi-loader projects)
  --artifact-path <path>      Artifact path relative to project root; auto-detected if empty
  --additional-mods <csv>     Comma-separated list of additional mod files (paths relative to project root)
  --download-runtime-deps <true|false>
                              If true and dependencies.yml exists, downloads runtime deps into ./run/mods
                              (default: true)
  --clean-run-dir <true|false>
                              If true, deletes ./run/mods contents before staging (default: true)
  -h, --help                  Show this help

Outputs (key=value):
  loader_type
  minecraft_version
  artifact_path
  test_dir
  mod_dir
  dependencies_count
EOF
}

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

project_root="."
loader=""
artifact_path=""
additional_mods=""
download_runtime_deps="true"
clean_run_dir="true"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --project-root)
      project_root="$2"
      shift 2
      ;;
    --loader)
      loader="$2"
      shift 2
      ;;
    --artifact-path)
      artifact_path="$2"
      shift 2
      ;;
    --additional-mods)
      additional_mods="$2"
      shift 2
      ;;
    --download-runtime-deps)
      download_runtime_deps="$2"
      shift 2
      ;;
    --clean-run-dir)
      clean_run_dir="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "ERROR: unknown argument: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

case "$clean_run_dir" in
  true|false) ;;
  *)
    echo "ERROR: --clean-run-dir must be true|false" >&2
    exit 1
    ;;
esac

case "$download_runtime_deps" in
  true|false) ;;
  *)
    echo "ERROR: --download-runtime-deps must be true|false" >&2
    exit 1
    ;;
esac

# Detect canonical properties and loader defaults.
detect_out="$(${SCRIPT_DIR}/quick-detect.sh --project-root "$project_root")"

minecraft_version="$(echo "$detect_out" | sed -n 's/^minecraft_version=//p' | head -n 1)"
loader_multi="$(echo "$detect_out" | sed -n 's/^loader_multi=//p' | head -n 1)"
loader_type="$(echo "$detect_out" | sed -n 's/^loader_type=//p' | head -n 1)"
active_loaders="$(echo "$detect_out" | sed -n 's/^active_loaders=//p' | head -n 1)"

if [[ -z "$minecraft_version" ]]; then
  echo "ERROR: failed to read minecraft_version from quick-detect output" >&2
  exit 1
fi

if [[ "$loader_multi" == "true" ]]; then
  if [[ -z "$loader" ]]; then
    echo "ERROR: multi-loader project requires --loader (active_loaders=${active_loaders})" >&2
    exit 1
  fi
  loader_type="$loader"
else
  if [[ -n "$loader" && "$loader" != "$loader_type" ]]; then
    echo "ERROR: --loader was provided but project is single-loader (${loader_type})" >&2
    exit 1
  fi
fi

case "$loader_type" in
  forge|neoforge|fabric) ;;
  *)
    echo "ERROR: unsupported loader_type=${loader_type}" >&2
    exit 1
    ;;
esac

# Resolve artifact path (relative to project root).
if [[ -z "$artifact_path" ]]; then
  if [[ "$loader_multi" == "true" ]]; then
    artifact_out="$(${SCRIPT_DIR}/compute-artifact-path.sh --project-root "$project_root" --loader "$loader_type")"
  else
    artifact_out="$(${SCRIPT_DIR}/compute-artifact-path.sh --project-root "$project_root")"
  fi
  artifact_path="$(echo "$artifact_out" | sed -n 's/^artifact_path=//p' | head -n 1)"
fi

if [[ -z "$artifact_path" ]]; then
  echo "ERROR: artifact_path could not be resolved" >&2
  exit 1
fi

artifact_abs="${project_root%/}/${artifact_path}"
if [[ ! -f "$artifact_abs" ]]; then
  echo "ERROR: expected artifact missing: ${artifact_path}" >&2
  exit 1
fi

# Prepare directories expected by headlesshq/mc-runtime-test (fixed: ./run/mods).
test_dir="run"
mod_dir="run/mods"

mkdir -p "$mod_dir"

if [[ "$clean_run_dir" == "true" ]]; then
  # Keep the directory, clear contents.
  shopt -s nullglob
  rm -rf "${mod_dir}/"*
  shopt -u nullglob
fi

# Copy the primary mod artifact.
cp "$artifact_abs" "${mod_dir}/"

# Copy any additional mods.
dependencies_count=0
if [[ -n "$additional_mods" ]]; then
  IFS=',' read -r -a mods <<< "$additional_mods"
  for mod_rel in "${mods[@]}"; do
    mod_rel_trimmed="$(echo "$mod_rel" | xargs)"
    [[ -n "$mod_rel_trimmed" ]] || continue

    mod_abs="${project_root%/}/${mod_rel_trimmed}"
    if [[ ! -f "$mod_abs" ]]; then
      echo "ERROR: additional mod not found: ${mod_rel_trimmed}" >&2
      exit 1
    fi

    cp "$mod_abs" "$mod_dir/"
    dependencies_count=$((dependencies_count + 1))
  done
fi

# Download runtime dependencies from dependencies.yml (optional enrichment) if present.
if [[ "$download_runtime_deps" == "true" ]]; then
  deps_out="$(${SCRIPT_DIR}/download-runtime-deps.sh \
    --project-root "$project_root" \
    --loader "$loader_type" \
    --minecraft-version "$minecraft_version" \
    --dest-dir "$mod_dir" || true)"

  deps_present="$(echo "$deps_out" | sed -n 's/^dependencies_present=//p' | head -n 1)"
  deps_downloaded="$(echo "$deps_out" | sed -n 's/^downloaded_count=//p' | head -n 1)"

  if [[ "$deps_present" == "true" ]]; then
    if [[ -z "$deps_downloaded" ]]; then
      echo "ERROR: failed to read downloaded_count from download-runtime-deps output" >&2
      exit 1
    fi
    if ! [[ "$deps_downloaded" =~ ^[0-9]+$ ]]; then
      echo "ERROR: invalid downloaded_count from download-runtime-deps: ${deps_downloaded}" >&2
      exit 1
    fi
    dependencies_count=$((dependencies_count + deps_downloaded))
  fi
fi

{
  echo "loader_type=${loader_type}"
  echo "minecraft_version=${minecraft_version}"
  echo "artifact_path=${artifact_path}"
  echo "test_dir=${test_dir}"
  echo "mod_dir=${mod_dir}"
  echo "dependencies_count=${dependencies_count}"
}
