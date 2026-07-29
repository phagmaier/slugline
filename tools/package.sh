#!/usr/bin/env bash
# Build and stage the versioned Linux x86_64 release tarball.
#
#   ./tools/package.sh
#   ./tools/package.sh --no-build  # reuse an existing release bundle
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

usage() {
  cat <<'EOF'
Usage: tools/package.sh [--no-build]

Build (unless --no-build is supplied), stage, and archive the Slugline Linux
x86_64 release bundle.
EOF
}

case "${1:-}" in
  "")
    BUILD=1
    ;;
  --no-build)
    BUILD=0
    ;;
  -h|--help)
    usage
    exit 0
    ;;
  *)
    usage >&2
    exit 2
    ;;
esac
[ "$#" -le 1 ] || { usage >&2; exit 2; }

[ "$(uname -m)" = "x86_64" ] || {
  echo "This release process supports Linux x86_64 only." >&2
  exit 1
}

VERSION="$("$ROOT/tools/release_version.sh")"
BUNDLE="$ROOT/app/build/linux/x64/release/bundle"
DIST="$ROOT/dist"
STAGE_NAME="slugline-$VERSION-linux-x86_64"
STAGE="$DIST/$STAGE_NAME"
TARBALL="$DIST/$STAGE_NAME.tar.gz"

if [ "$BUILD" -eq 1 ]; then
  echo "==> Building the release"
  # Rust panic/location strings must not reveal the checkout path in public
  # artifacts. Preserve caller flags while remapping this checkout consistently.
  export RUSTFLAGS="${RUSTFLAGS:+$RUSTFLAGS }--remap-path-prefix=$ROOT=/usr/src/slugline --remap-path-prefix=${HOME:?HOME must be set}=/usr/src"
  (cd "$ROOT/app" && flutter build linux --release)
fi

[ -x "$BUNDLE/slugline" ] || {
  echo "No release bundle at $BUNDLE" >&2
  echo "Run tools/package.sh without --no-build first." >&2
  exit 1
}

for required in \
  data/icudtl.dat \
  data/flutter_assets/FontManifest.json \
  data/flutter_assets/fonts/CourierPrime-Regular.ttf \
  data/flutter_assets/fonts/CourierPrime-Bold.ttf \
  data/flutter_assets/fonts/CourierPrime-Italic.ttf \
  data/flutter_assets/fonts/CourierPrime-BoldItalic.ttf \
  lib/libapp.so \
  lib/libflutter_linux_gtk.so \
  lib/libslugline_bridge.so; do
  [ -f "$BUNDLE/$required" ] || {
    echo "Release bundle is missing $required" >&2
    exit 1
  }
done

mkdir -p "$DIST"
WORK="$(mktemp -d "$DIST/.package.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
NEXT_STAGE="$WORK/$STAGE_NAME"

echo "==> Staging $STAGE_NAME"
install -d "$NEXT_STAGE/bundle"
cp -a "$BUNDLE/." "$NEXT_STAGE/bundle/"
install -Dm644 packaging/com.phagmaier.slugline.desktop \
  "$NEXT_STAGE/share/applications/com.phagmaier.slugline.desktop"
install -Dm644 packaging/com.phagmaier.slugline.metainfo.xml \
  "$NEXT_STAGE/share/metainfo/com.phagmaier.slugline.metainfo.xml"
install -Dm644 packaging/com.phagmaier.slugline.mime.xml \
  "$NEXT_STAGE/share/mime/packages/com.phagmaier.slugline.xml"
install -Dm644 packaging/icons/com.phagmaier.slugline.svg \
  "$NEXT_STAGE/share/icons/hicolor/scalable/apps/com.phagmaier.slugline.svg"
install -Dm644 LICENSE "$NEXT_STAGE/share/licenses/slugline/LICENSE"
install -Dm644 crates/render_pdf/fonts/OFL.txt \
  "$NEXT_STAGE/share/licenses/slugline/OFL-CourierPrime.txt"
install -Dm644 CHANGELOG.md "$NEXT_STAGE/share/doc/slugline/CHANGELOG.md"
install -Dm644 README.md "$NEXT_STAGE/share/doc/slugline/README.md"

cat > "$NEXT_STAGE/install.sh" <<'INSTALL'
#!/usr/bin/env bash
# Install Slugline into ~/.local, or into a caller-provided absolute prefix:
#
#   ./install.sh
#   ./install.sh /usr/local
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ "$#" -gt 1 ]; then
  echo "Usage: ./install.sh [PREFIX]" >&2
  exit 2
fi
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

install -d "$PREFIX/lib/slugline"
cp -a "$HERE/bundle/." "$PREFIX/lib/slugline/"

install -d "$PREFIX/bin"
cat > "$PREFIX/bin/slugline" <<'LAUNCHER'
#!/bin/sh
set -eu
bindir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
exec "$bindir/../lib/slugline/slugline" "$@"
LAUNCHER
chmod 755 "$PREFIX/bin/slugline"

cp -a "$HERE/share/." "$PREFIX/share/"

refresh() {
  tool="$1"
  shift
  if command -v "$tool" >/dev/null 2>&1; then
    if ! "$tool" "$@"; then
      printf 'Warning: %s cache refresh failed; installed files are intact.\n' \
        "$tool" >&2
    fi
  fi
}
refresh update-desktop-database "$PREFIX/share/applications"
refresh update-mime-database "$PREFIX/share/mime"
refresh gtk-update-icon-cache -f -t "$PREFIX/share/icons/hicolor"

echo "Installed Slugline to $PREFIX."
case ":${PATH:-}:" in
  *":$PREFIX/bin:"*) ;;
  *) echo "Add $PREFIX/bin to PATH to run 'slugline' from a shell." ;;
esac
INSTALL
chmod 755 "$NEXT_STAGE/install.sh"

cat > "$NEXT_STAGE/uninstall.sh" <<'UNINSTALL'
#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -gt 1 ]; then
  echo "Usage: ./uninstall.sh [PREFIX]" >&2
  exit 2
fi
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
UNINSTALL
chmod 755 "$NEXT_STAGE/uninstall.sh"

# Replace only this version's ignored staging directory.
rm -rf -- "$STAGE"
mv "$NEXT_STAGE" "$STAGE"

echo "==> Creating $(basename "$TARBALL")"
SOURCE_DATE_EPOCH="${SOURCE_DATE_EPOCH:-$(git log -1 --format=%ct)}"
TMP_TARBALL="$WORK/$(basename "$TARBALL")"
tar \
  --sort=name \
  --mtime="@$SOURCE_DATE_EPOCH" \
  --owner=0 \
  --group=0 \
  --numeric-owner \
  --format=posix \
  --pax-option=delete=atime,delete=ctime \
  -C "$DIST" \
  -cf - \
  "$STAGE_NAME" |
  gzip -n > "$TMP_TARBALL"
mv "$TMP_TARBALL" "$TARBALL"

printf '%s\n' "$TARBALL"
