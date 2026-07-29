#!/usr/bin/env bash
# Create the annotated release tag after the full preflight has passed.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

if [ -n "$(git status --porcelain)" ]; then
  echo "The working tree is not clean; commit or remove changes before tagging." >&2
  git status --short >&2
  exit 1
fi

VERSION="$("$ROOT/tools/release_version.sh")"
TAG="v$VERSION"
python3 tools/check_version.py

if git rev-parse --verify --quiet "refs/tags/$TAG" >/dev/null; then
  echo "Tag already exists: $TAG" >&2
  exit 1
fi

git tag -a "$TAG" -m "Slugline $VERSION"
echo "Created annotated tag $TAG."
echo "Review it with: git show $TAG"
echo "Push it explicitly with: git push origin $TAG"
