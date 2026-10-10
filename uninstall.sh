#!/usr/bin/env bash
# Uninstall Slugline from ~/.local or a given prefix.
#
#   ./uninstall.sh
#   ./uninstall.sh /usr/local
#
# When the staged dist uninstaller exists it owns the removal; this wrapper
# delegates to it. When dist/ has been cleaned, the fallback below removes
# the same package-owned paths. User scripts, preferences, backups, and
# recovery data live elsewhere and are never touched.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

usage() {
  cat <<'EOF'
Usage: ./uninstall.sh [PREFIX]

Remove the Slugline installation at PREFIX (default ~/.local).
EOF
}

if [ "$#" -gt 1 ]; then
  usage >&2
  exit 2
fi
case "${1:-}" in
  -h|--help)
    usage
    exit 0
    ;;
esac

# Delegate to the staged uninstaller when it is available so there is one
# source of truth for the installed layout. Pass the prefix through only
# when the caller gave one, preserving the staged script's own default.
if VERSION="$("$ROOT/tools/release_version.sh" 2>/dev/null)"; then
  STAGE="$ROOT/dist/slugline-$VERSION-linux-x86_64"
  if [ -x "$STAGE/uninstall.sh" ]; then
    if [ "$#" -eq 1 ]; then
      exec "$STAGE/uninstall.sh" "$1"
    else
      exec "$STAGE/uninstall.sh"
    fi
  fi
fi

# Fallback for when dist/ is gone. Keep in sync with the uninstaller that
# tools/package.sh stages (and only those package-owned paths).
if [ "$#" -eq 1 ]; then
  PREFIX="$1"
else
  : "${HOME:?HOME must be set when no installation prefix is supplied}"
  PREFIX="$HOME/.local"
fi
case "$PREFIX" in
  /*) ;;
  *) echo "Installation prefix must be an absolute path: $PREFIX" >&2; exit 2 ;;
esac

# These are the package-owned paths and only these paths. Slugline's scripts,
# preferences, backups, library index, and recovery journal live elsewhere.
rm -rf -- "$PREFIX/lib/slugline"
rm -f -- \
  "$PREFIX/bin/slugline" \
  "$PREFIX/share/applications/com.phagmaier.slugline.desktop" \
  "$PREFIX/share/metainfo/com.phagmaier.slugline.metainfo.xml" \
  "$PREFIX/share/mime/packages/com.phagmaier.slugline.xml" \
  "$PREFIX/share/icons/hicolor/scalable/apps/com.phagmaier.slugline.svg"
rm -rf -- \
  "$PREFIX/share/licenses/slugline" \
  "$PREFIX/share/doc/slugline"

echo "Removed Slugline from $PREFIX. User scripts and application data were untouched."
