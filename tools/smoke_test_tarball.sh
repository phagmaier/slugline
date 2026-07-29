#!/usr/bin/env bash
# Validate the release tarball without relying on the source-tree bundle.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="$("$ROOT/tools/release_version.sh")"
EXPECTED_NAME="slugline-$VERSION-linux-x86_64.tar.gz"
ARCHIVE="${1:-$ROOT/dist/$EXPECTED_NAME}"

[ -f "$ARCHIVE" ] || { echo "Tarball not found: $ARCHIVE" >&2; exit 1; }
[ "$(basename "$ARCHIVE")" = "$EXPECTED_NAME" ] || {
  echo "Expected artifact name $EXPECTED_NAME, got $(basename "$ARCHIVE")" >&2
  exit 1
}

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
LISTING="$WORK/listing"
tar -tzf "$ARCHIVE" > "$LISTING"

python3 - "$LISTING" <<'PY'
import sys
from pathlib import PurePosixPath

entries = [line.rstrip("\n") for line in open(sys.argv[1], encoding="utf-8")]
if not entries:
    raise SystemExit("archive is empty")
for entry in entries:
    path = PurePosixPath(entry)
    if path.is_absolute() or ".." in path.parts:
        raise SystemExit(f"unsafe archive path: {entry}")
PY

tar -xzf "$ARCHIVE" -C "$WORK"
STAGE="$WORK/slugline-$VERSION-linux-x86_64"
BUNDLE="$STAGE/bundle"

for required in \
  bundle/slugline \
  bundle/data/icudtl.dat \
  bundle/data/flutter_assets/FontManifest.json \
  bundle/data/flutter_assets/fonts/CourierPrime-Regular.ttf \
  bundle/data/flutter_assets/fonts/CourierPrime-Bold.ttf \
  bundle/data/flutter_assets/fonts/CourierPrime-Italic.ttf \
  bundle/data/flutter_assets/fonts/CourierPrime-BoldItalic.ttf \
  bundle/lib/libapp.so \
  bundle/lib/libflutter_linux_gtk.so \
  bundle/lib/libslugline_bridge.so \
  share/applications/com.phagmaier.slugline.desktop \
  share/metainfo/com.phagmaier.slugline.metainfo.xml \
  share/mime/packages/com.phagmaier.slugline.xml \
  share/icons/hicolor/scalable/apps/com.phagmaier.slugline.svg \
  share/licenses/slugline/LICENSE \
  share/licenses/slugline/OFL-CourierPrime.txt \
  install.sh \
  uninstall.sh; do
  [ -e "$STAGE/$required" ] || { echo "Missing $required" >&2; exit 1; }
done

file "$BUNDLE/slugline" | grep -q 'ELF 64-bit.*x86-64'
readelf -d "$BUNDLE/slugline" |
  grep -F "Library runpath: [\$ORIGIN/lib]" >/dev/null

for object in \
  "$BUNDLE/slugline" \
  "$BUNDLE/lib/libflutter_linux_gtk.so" \
  "$BUNDLE/lib/libslugline_bridge.so"; do
  if ldd "$object" | grep -q 'not found'; then
    echo "Unresolved library dependency in $object" >&2
    ldd "$object" >&2
    exit 1
  fi
done

[ "$("$BUNDLE/slugline" --version)" = "slugline $VERSION" ]
"$BUNDLE/slugline" --help |
  grep -q 'keyboard-driven Fountain screenplay editor'

if grep -aR -F -l --exclude=README.md --exclude=CHANGELOG.md "$ROOT" "$STAGE" \
    > "$WORK/source-paths"; then
  echo "Artifact embeds the source checkout path:" >&2
  sed 's/^/  /' "$WORK/source-paths" >&2
  exit 1
fi
if grep -aR -F -l --exclude=README.md --exclude=CHANGELOG.md "${HOME:?}" "$STAGE" \
    > "$WORK/build-home-paths"; then
  echo "Artifact embeds the build user's home path:" >&2
  sed 's/^/  /' "$WORK/build-home-paths" >&2
  exit 1
fi

if command -v desktop-file-validate >/dev/null 2>&1; then
  desktop-file-validate \
    "$STAGE/share/applications/com.phagmaier.slugline.desktop"
fi
if command -v appstreamcli >/dev/null 2>&1; then
  appstreamcli validate --no-net \
    "$STAGE/share/metainfo/com.phagmaier.slugline.metainfo.xml"
fi

# Exercise both supported installer modes and prove the uninstaller leaves
# application data alone.
CUSTOM_PREFIX="$WORK/custom-prefix"
"$STAGE/install.sh" "$CUSTOM_PREFIX"
[ "$("$CUSTOM_PREFIX/bin/slugline" --version)" = "slugline $VERSION" ]
"$CUSTOM_PREFIX/bin/slugline" --help |
  grep -q 'keyboard-driven Fountain screenplay editor'
"$STAGE/uninstall.sh" "$CUSTOM_PREFIX"
[ ! -e "$CUSTOM_PREFIX/bin/slugline" ]
[ ! -e "$CUSTOM_PREFIX/lib/slugline" ]

TEST_HOME="$WORK/home"
mkdir -p "$TEST_HOME/.config/slugline" "$TEST_HOME/.local/state/slugline"
printf 'keep\n' > "$TEST_HOME/.config/slugline/preferences"
printf 'keep\n' > "$TEST_HOME/.local/state/slugline/recovery"
HOME="$TEST_HOME" "$STAGE/install.sh"
HOME="$TEST_HOME" "$STAGE/uninstall.sh"
[ -f "$TEST_HOME/.config/slugline/preferences" ]
[ -f "$TEST_HOME/.local/state/slugline/recovery" ]

echo "Tarball smoke test passed: $(basename "$ARCHIVE")"
