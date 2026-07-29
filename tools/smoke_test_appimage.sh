#!/usr/bin/env bash
# Validate an AppImage through its built-in non-FUSE extraction path.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="$("$ROOT/tools/release_version.sh")"
EXPECTED_NAME="Slugline-$VERSION-x86_64.AppImage"
IMAGE="${1:-$ROOT/dist/$EXPECTED_NAME}"

[ -x "$IMAGE" ] || { echo "AppImage not found or not executable: $IMAGE" >&2; exit 1; }
IMAGE="$(realpath -- "$IMAGE")"
[ "$(basename "$IMAGE")" = "$EXPECTED_NAME" ] || {
  echo "Expected artifact name $EXPECTED_NAME, got $(basename "$IMAGE")" >&2
  exit 1
}
file "$IMAGE" | grep -q 'ELF 64-bit.*x86-64'
[ "$(dd if="$IMAGE" bs=1 skip=8 count=3 status=none)" = "$(printf 'AI\002')" ] || {
  echo "Not a type-2 AppImage: $IMAGE" >&2
  exit 1
}

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/home"
(
  cd "$WORK"
  HOME="$WORK/home" "$IMAGE" --appimage-extract >/dev/null
)
APPDIR="$WORK/squashfs-root"

for required in \
  AppRun \
  .DirIcon \
  com.phagmaier.slugline.desktop \
  com.phagmaier.slugline.svg \
  usr/lib/slugline/slugline \
  usr/lib/slugline/data/icudtl.dat \
  usr/lib/slugline/data/flutter_assets/FontManifest.json \
  usr/lib/slugline/data/flutter_assets/fonts/CourierPrime-Regular.ttf \
  usr/lib/slugline/data/flutter_assets/fonts/CourierPrime-Bold.ttf \
  usr/lib/slugline/data/flutter_assets/fonts/CourierPrime-Italic.ttf \
  usr/lib/slugline/data/flutter_assets/fonts/CourierPrime-BoldItalic.ttf \
  usr/lib/slugline/lib/libapp.so \
  usr/lib/slugline/lib/libflutter_linux_gtk.so \
  usr/lib/slugline/lib/libslugline_bridge.so \
  usr/share/applications/com.phagmaier.slugline.desktop \
  usr/share/mime/packages/com.phagmaier.slugline.xml \
  usr/share/icons/hicolor/scalable/apps/com.phagmaier.slugline.svg \
  usr/share/licenses/slugline/LICENSE \
  usr/share/licenses/slugline/OFL-CourierPrime.txt; do
  [ -e "$APPDIR/$required" ] || { echo "Missing $required" >&2; exit 1; }
done

grep -Eq '^Exec=slugline %f$' \
  "$APPDIR/usr/share/applications/com.phagmaier.slugline.desktop"
grep -Eq '^MimeType=text/x-fountain;$' \
  "$APPDIR/usr/share/applications/com.phagmaier.slugline.desktop"

[ "$(env APPDIR="$APPDIR" "$APPDIR/AppRun" --version)" = "slugline $VERSION" ]
env APPDIR="$APPDIR" "$APPDIR/AppRun" --help |
  grep -q 'keyboard-driven Fountain screenplay editor'

LIBRARY_PATH="$APPDIR/usr/lib/slugline/lib:$APPDIR/usr/lib"
for object in \
  "$APPDIR/usr/lib/slugline/slugline" \
  "$APPDIR/usr/lib/slugline/lib/libflutter_linux_gtk.so" \
  "$APPDIR/usr/lib/slugline/lib/libslugline_bridge.so"; do
  if LD_LIBRARY_PATH="$LIBRARY_PATH" ldd "$object" | grep -q 'not found'; then
    echo "Unresolved AppImage library dependency in $object" >&2
    LD_LIBRARY_PATH="$LIBRARY_PATH" ldd "$object" >&2
    exit 1
  fi
done

if grep -aR -F -l --exclude=README.md --exclude=CHANGELOG.md "$ROOT" "$APPDIR" \
    > "$WORK/source-paths"; then
  echo "AppImage embeds the source checkout path:" >&2
  sed 's/^/  /' "$WORK/source-paths" >&2
  exit 1
fi
if grep -aR -F -l --exclude=README.md --exclude=CHANGELOG.md "${HOME:?}" "$APPDIR" \
    > "$WORK/build-home-paths"; then
  echo "AppImage embeds the build user's home path:" >&2
  sed 's/^/  /' "$WORK/build-home-paths" >&2
  exit 1
fi

if command -v desktop-file-validate >/dev/null 2>&1; then
  desktop-file-validate \
    "$APPDIR/usr/share/applications/com.phagmaier.slugline.desktop"
fi

# Direct execution is an additional FUSE/runtime check. The extracted AppRun
# checks above remain mandatory on kernels or containers where FUSE is blocked.
if DIRECT_VERSION="$(HOME="$WORK/home" "$IMAGE" --version 2>"$WORK/direct.err")"; then
  [ "$DIRECT_VERSION" = "slugline $VERSION" ]
  HOME="$WORK/home" "$IMAGE" --help |
    grep -q 'keyboard-driven Fountain screenplay editor'
  echo "Direct AppImage execution passed."
else
  echo "Direct AppImage execution unavailable; extraction-based CLI tests passed."
  sed -n '1,5p' "$WORK/direct.err"
fi

echo "AppImage smoke test passed: $(basename "$IMAGE")"
