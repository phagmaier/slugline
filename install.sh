#!/usr/bin/env bash
# Install Slugline from a source checkout into ~/.local or a given prefix.
#
#   ./install.sh
#   ./install.sh /usr/local
#   ./install.sh --no-build
#   ./install.sh /usr/local --no-build
#
# Without --no-build this builds the release with tools/package.sh and then
# runs the staged dist installer. With --no-build it reuses the existing
# staged bundle via tools/package.sh --no-build. The staged installer owns
# the file layout; this wrapper only decides what to build and which prefix
# to hand it.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

usage() {
  cat <<'EOF'
Usage: ./install.sh [PREFIX] [--no-build]

Build the release (unless --no-build is supplied) and install it. PREFIX
defaults to ~/.local and must be an absolute path.
EOF
}

PREFIX=""
NO_BUILD=0

for arg in "$@"; do
  case "$arg" in
    -h|--help)
      usage
      exit 0
      ;;
    --no-build)
      NO_BUILD=1
      ;;
    -*)
      echo "Unknown option: $arg" >&2
      usage >&2
      exit 2
      ;;
    *)
      if [ -n "$PREFIX" ]; then
        echo "Only one installation prefix may be supplied." >&2
        usage >&2
        exit 2
      fi
      PREFIX="$arg"
      ;;
  esac
done

if [ -z "$PREFIX" ]; then
  : "${HOME:?HOME must be set when no installation prefix is supplied}"
  PREFIX="$HOME/.local"
fi
case "$PREFIX" in
  /*) ;;
  *) echo "Installation prefix must be an absolute path: $PREFIX" >&2; exit 2 ;;
esac

VERSION="$("$ROOT/tools/release_version.sh")"
STAGE="$ROOT/dist/slugline-$VERSION-linux-x86_64"

if [ "$NO_BUILD" -eq 1 ]; then
  "$ROOT/tools/package.sh" --no-build
else
  "$ROOT/tools/package.sh"
fi

[ -x "$STAGE/install.sh" ] || {
  echo "Staged installer not found at $STAGE/install.sh" >&2
  exit 1
}

exec "$STAGE/install.sh" "$PREFIX"
