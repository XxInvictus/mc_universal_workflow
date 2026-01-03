#!/usr/bin/env bash
# ensure-tag-exists.sh
# Idempotently ensures a lightweight git tag ref exists in the GitHub repo.
#
# If the tag already exists:
#   - succeeds if it points to the expected SHA
#   - fails if it points elsewhere (mode=strict)
#   - updates it to the expected SHA (mode=move)
# If the tag does not exist:
#   - creates it pointing to the expected SHA
#
# Requires: gh (GitHub CLI) and GH_TOKEN.

set -euo pipefail

fail() {
  local message="$1"
  echo "ERROR: ${message}" >&2
  exit 1
}

usage() {
  cat <<'EOF'
Usage: ensure-tag-exists.sh [OPTIONS]

Options:
  --repo <owner/repo>   GitHub repository (defaults to GITHUB_REPOSITORY)
  --tag <tag>           Tag name (e.g., 1.20.1-1.2.3)
  --sha <sha>           Commit SHA the tag must point to
  --mode <mode>         Tag behavior when it already exists: strict|move (default: strict)
  -h, --help            Show this help

Environment:
  GH_TOKEN must be set for authentication.
EOF
}

repo="${GITHUB_REPOSITORY:-}"
tag=""
sha=""
mode="strict"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo)
      repo="${2:-}"
      shift 2
      ;;
    --tag)
      tag="${2:-}"
      shift 2
      ;;
    --sha)
      sha="${2:-}"
      shift 2
      ;;
    --mode)
      mode="${2:-}"
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

[[ -n "$repo" ]] || fail "--repo is required (or set GITHUB_REPOSITORY)"
[[ -n "$tag" ]] || fail "--tag is required"
[[ -n "$sha" ]] || fail "--sha is required"

case "$mode" in
  strict|move) ;;
  *) fail "--mode must be one of: strict|move" ;;
esac

command -v gh >/dev/null 2>&1 || fail "gh CLI is required but not found on PATH"
[[ -n "${GH_TOKEN:-}" ]] || fail "GH_TOKEN is required for gh api authentication"

ref_path="repos/${repo}/git/ref/tags/${tag}"

set +e
existing_sha="$(gh api "$ref_path" --jq '.object.sha' 2>/dev/null)"
status=$?
set -e

if [[ $status -eq 0 ]]; then
  if [[ "$existing_sha" != "$sha" ]]; then
    if [[ "$mode" == "move" ]]; then
      gh api -X PATCH "$ref_path" \
        -f "sha=${sha}" \
        -f "force=true" >/dev/null
      echo "Updated tag '${tag}' from ${existing_sha} to ${sha}" >&2
      exit 0
    fi
    fail "Tag '${tag}' already exists but points to ${existing_sha}, expected ${sha}"
  fi
  echo "Tag '${tag}' already exists at ${sha}" >&2
  exit 0
fi

# If we got here, the ref likely doesn't exist (404). Create it.
# Note: this creates a lightweight tag ref (refs/tags/<tag>) pointing to a commit SHA.
create_path="repos/${repo}/git/refs"

gh api -X POST "$create_path" \
  -f "ref=refs/tags/${tag}" \
  -f "sha=${sha}" >/dev/null

echo "Created tag '${tag}' at ${sha}" >&2
