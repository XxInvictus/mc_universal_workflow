#!/usr/bin/env bash
# validate-artifact-path.sh
# Computes the enforced artifact path and asserts the artifact exists.

set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  validate-artifact-path.sh --project-root <path> [--loader <forge|neoforge|fabric>]

Exits non-zero if the computed artifact path does not exist.
EOF
}

fail() {
  local message="$1"
  echo "ERROR: ${message}" >&2
  exit 1
}

project_root=""
loader=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --project-root)
      project_root="${2:-}"
      [[ -n "$project_root" ]] || fail "--project-root requires a value"
      shift 2
      ;;
    --loader)
      loader="${2:-}"
      [[ -n "$loader" ]] || fail "--loader requires a value"
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

[[ -n "$project_root" ]] || fail "--project-root is required"

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

compute_args=("--project-root" "$project_root")
if [[ -n "$loader" ]]; then
  compute_args+=("--loader" "$loader")
fi

computed="$(bash "${script_dir}/compute-artifact-path.sh" "${compute_args[@]}" | sed -n 's/^artifact_path=//p' | head -n 1)"

if [[ -z "$computed" ]]; then
  fail "failed to compute artifact_path"
fi

artifact_abs="${project_root%/}/${computed}"
if [[ ! -f "$artifact_abs" ]]; then
  echo "ERROR: artifact does not exist: ${computed}" >&2
  echo "INFO: expected absolute path: ${artifact_abs}" >&2
  echo "INFO: listing ${project_root%/}/build/libs (if present):" >&2
  ls -la "${project_root%/}/build/libs" 2>/dev/null || true
  echo "INFO: searching for jars under ${project_root%/}/build (maxdepth 6):" >&2
  find "${project_root%/}/build" -maxdepth 6 -type f -name '*.jar' -print 2>/dev/null || true
  echo "INFO: artifact naming must match the enforced contract computed from gradle.properties." >&2
  exit 1
fi

echo "artifact_path=${computed}"
