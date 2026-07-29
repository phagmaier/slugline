#!/usr/bin/env bash
# Print the public release version owned by app/pubspec.yaml.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="$(
  sed -n 's/^version:[[:space:]]*\([0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*\).*/\1/p' \
    "$ROOT/app/pubspec.yaml"
)"
[ -n "$VERSION" ] || {
  echo "No semantic release version found in app/pubspec.yaml" >&2
  exit 1
}
printf '%s\n' "$VERSION"
