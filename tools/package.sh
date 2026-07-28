#!/usr/bin/env bash
# Builds the release and lays out a distributable tree.
#
#   ./tools/package.sh              # build, then stage and tar
#   ./tools/package.sh --no-build   # stage from a bundle that is already there
#
# Produces `dist/slugline-<version>-linux-x64.tar.gz`, holding the bundle, the
# desktop entry, the icon, the MIME registration, the licences, and an
# `install.sh` that puts them where the freedesktop specifications say.
#
# This is the plain-tarball leg of §Phase 11. The Flatpak manifest is in
# `packaging/flatpak/` and is the primary distribution; this is what someone
# who does not want Flatpak uses, and what an AppImage is assembled from.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

VERSION="$(sed -n 's/^version: \([0-9.]*\).*/\1/p' app/pubspec.yaml)"
[ -n "$VERSION" ] || { echo "No version in app/pubspec.yaml" >&2; exit 1; }

BUNDLE="app/build/linux/x64/release/bundle"
STAGE="dist/slugline-$VERSION-linux-x64"

if [ "${1:-}" != "--no-build" ]; then
  echo "==> Building the release"
  (cd app && flutter build linux --release)
fi
[ -x "$BUNDLE/slugline" ] || { echo "No release bundle at $BUNDLE" >&2; exit 1; }

echo "==> Staging $STAGE"
rm -rf "$STAGE"
mkdir -p "$STAGE"

cp -r "$BUNDLE" "$STAGE/bundle"
install -Dm644 packaging/com.phagmaier.slugline.desktop \
  "$STAGE/share/applications/com.phagmaier.slugline.desktop"
install -Dm644 packaging/com.phagmaier.slugline.metainfo.xml \
  "$STAGE/share/metainfo/com.phagmaier.slugline.metainfo.xml"
install -Dm644 packaging/com.phagmaier.slugline.mime.xml \
  "$STAGE/share/mime/packages/com.phagmaier.slugline.xml"
install -Dm644 packaging/icons/com.phagmaier.slugline.svg \
  "$STAGE/share/icons/hicolor/scalable/apps/com.phagmaier.slugline.svg"

# Licence compliance: this project's own licence, and the vendored font's. The
# OFL requires its text to travel with the font, and the font is compiled into
# the PDF writer rather than shipped as a file — so this is the copy that
# discharges it.
install -Dm644 LICENSE "$STAGE/share/licenses/slugline/LICENSE"
install -Dm644 crates/render_pdf/fonts/OFL.txt \
  "$STAGE/share/licenses/slugline/OFL-CourierPrime.txt"
install -Dm644 CHANGELOG.md "$STAGE/share/doc/slugline/CHANGELOG.md"
install -Dm644 README.md "$STAGE/share/doc/slugline/README.md"

cat > "$STAGE/install.sh" <<'INSTALL'
#!/usr/bin/env bash
# Installs Slugline. Defaults to a single user; pass a prefix for system-wide:
#
#   ./install.sh                    # ~/.local
#   sudo ./install.sh /usr/local    # everyone
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PREFIX="${1:-$HOME/.local}"

install -d "$PREFIX/lib/slugline"
cp -r "$HERE/bundle/." "$PREFIX/lib/slugline/"

# A launcher rather than a symlink: the executable finds its `data/` and `lib/`
# relative to its own real path, so it has to be started from where it lives.
install -d "$PREFIX/bin"
cat > "$PREFIX/bin/slugline" <<LAUNCHER
#!/bin/sh
exec "$PREFIX/lib/slugline/slugline" "\$@"
LAUNCHER
chmod 755 "$PREFIX/bin/slugline"

cp -r "$HERE/share/." "$PREFIX/share/"

# Best effort: these only refresh caches, and a missing tool is not a failure.
update-desktop-database "$PREFIX/share/applications" 2>/dev/null || true
update-mime-database "$PREFIX/share/mime" 2>/dev/null || true
gtk-update-icon-cache -f -t "$PREFIX/share/icons/hicolor" 2>/dev/null || true

echo "Installed to $PREFIX."
case ":$PATH:" in
  *":$PREFIX/bin:"*) ;;
  *) echo "Note: $PREFIX/bin is not on your PATH." ;;
esac
INSTALL
chmod 755 "$STAGE/install.sh"

cat > "$STAGE/uninstall.sh" <<'UNINSTALL'
#!/usr/bin/env bash
set -euo pipefail
PREFIX="${1:-$HOME/.local}"
rm -rf "$PREFIX/lib/slugline" "$PREFIX/bin/slugline"
rm -f "$PREFIX/share/applications/com.phagmaier.slugline.desktop" \
      "$PREFIX/share/metainfo/com.phagmaier.slugline.metainfo.xml" \
      "$PREFIX/share/mime/packages/com.phagmaier.slugline.xml" \
      "$PREFIX/share/icons/hicolor/scalable/apps/com.phagmaier.slugline.svg"
rm -rf "$PREFIX/share/licenses/slugline" "$PREFIX/share/doc/slugline"
echo "Removed from $PREFIX. Your scripts, preferences and backups are untouched."
UNINSTALL
chmod 755 "$STAGE/uninstall.sh"

echo "==> Tarring"
TARBALL="dist/slugline-$VERSION-linux-x64.tar.gz"
rm -f "$TARBALL"
tar -C dist -czf "$TARBALL" "slugline-$VERSION-linux-x64"

printf '\n%s\n' "$TARBALL  ($(du -h "$TARBALL" | cut -f1))"
