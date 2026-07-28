#!/usr/bin/env bash
# The AppImage leg of §Phase 11 — the secondary distribution, for anyone with
# neither Flatpak nor a package manager they trust.
#
#   ./tools/package.sh            # first: builds the release and stages it
#   ./tools/make_appimage.sh      # then: assembles dist/Slugline-<version>-x86_64.AppImage
#
# Needs `appimagetool` on PATH. It is a single downloaded binary; this script
# does not fetch it, because §1.2 says this project makes no network requests
# and a build script that quietly downloads a toolchain is exactly the habit
# that rule exists to prevent. Get it once, by hand, from
# https://github.com/AppImage/AppImageKit/releases.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

VERSION="$(sed -n 's/^version: \([0-9.]*\).*/\1/p' app/pubspec.yaml)"
STAGE="dist/slugline-$VERSION-linux-x64"
APPDIR="dist/Slugline.AppDir"

[ -d "$STAGE" ] || { echo "Run tools/package.sh first — no $STAGE" >&2; exit 1; }
command -v appimagetool >/dev/null || {
  echo "appimagetool is not on PATH; see the comment at the top of this script." >&2
  exit 2
}

echo "==> Building $APPDIR"
rm -rf "$APPDIR"
install -d "$APPDIR/usr/lib/slugline" "$APPDIR/usr/bin"
cp -r "$STAGE/bundle/." "$APPDIR/usr/lib/slugline/"
cp -r "$STAGE/share" "$APPDIR/usr/share"

# AppImage looks for these three at the top of the AppDir.
install -Dm644 "$STAGE/share/applications/com.phagmaier.slugline.desktop" \
  "$APPDIR/com.phagmaier.slugline.desktop"
install -Dm644 packaging/icons/com.phagmaier.slugline.svg \
  "$APPDIR/com.phagmaier.slugline.svg"
ln -sf com.phagmaier.slugline.svg "$APPDIR/.DirIcon"

cat > "$APPDIR/AppRun" <<'APPRUN'
#!/bin/sh
# The executable finds `data/` and `lib/` relative to its own path, so it is
# started where it lives rather than from usr/bin.
HERE="$(dirname "$(readlink -f "$0")")"
export XDG_DATA_DIRS="$HERE/usr/share:${XDG_DATA_DIRS:-/usr/local/share:/usr/share}"
exec "$HERE/usr/lib/slugline/slugline" "$@"
APPRUN
chmod 755 "$APPDIR/AppRun"

echo "==> Assembling"
OUT="dist/Slugline-$VERSION-x86_64.AppImage"
rm -f "$OUT"
# No network: appimagetool would otherwise try to fetch a signature key and an
# update-information stub.
ARCH=x86_64 appimagetool --no-appstream "$APPDIR" "$OUT"

printf '\n%s\n' "$OUT  ($(du -h "$OUT" | cut -f1))"
