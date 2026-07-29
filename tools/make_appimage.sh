#!/usr/bin/env bash
# Assemble the staged release into a Linux x86_64 AppImage with linuxdeploy.
#
#   LINUXDEPLOY=/path/to/linuxdeploy-x86_64.AppImage tools/make_appimage.sh
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

VERSION="$("$ROOT/tools/release_version.sh")"
STAGE="$ROOT/dist/slugline-$VERSION-linux-x86_64"
APPDIR="$ROOT/dist/Slugline.AppDir"
OUT="$ROOT/dist/Slugline-$VERSION-x86_64.AppImage"

[ "$(uname -m)" = "x86_64" ] || {
  echo "This release process supports Linux x86_64 only." >&2
  exit 1
}
[ -d "$STAGE" ] || {
  echo "No staged release at $STAGE; run tools/package.sh first." >&2
  exit 1
}

if [ -n "${LINUXDEPLOY:-}" ]; then
  DEPLOY_TOOL="$LINUXDEPLOY"
elif command -v linuxdeploy-x86_64.AppImage >/dev/null 2>&1; then
  DEPLOY_TOOL="$(command -v linuxdeploy-x86_64.AppImage)"
elif command -v linuxdeploy >/dev/null 2>&1; then
  DEPLOY_TOOL="$(command -v linuxdeploy)"
else
  cat >&2 <<'EOF'
linuxdeploy is not available.

Download a pinned linuxdeploy x86_64 AppImage, verify its published SHA-256,
make it executable, and set LINUXDEPLOY to its path. docs/RELEASING.md contains
the exact supported tool version and commands.
EOF
  exit 2
fi
[ -x "$DEPLOY_TOOL" ] || {
  echo "linuxdeploy is not executable: $DEPLOY_TOOL" >&2
  exit 2
}

WORK="$(mktemp -d "$ROOT/dist/.appimage.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
NEXT_APPDIR="$WORK/Slugline.AppDir"

echo "==> Building AppDir"
install -d "$NEXT_APPDIR/usr/lib/slugline"
cp -a "$STAGE/bundle/." "$NEXT_APPDIR/usr/lib/slugline/"
cp -a "$STAGE/share" "$NEXT_APPDIR/usr/"
# appimagetool still recognizes the historical appdata.xml suffix. Keep the
# canonical metainfo.xml and add a relative compatibility link.
ln -s com.phagmaier.slugline.metainfo.xml \
  "$NEXT_APPDIR/usr/share/metainfo/com.phagmaier.slugline.appdata.xml"

install -Dm644 "$STAGE/share/applications/com.phagmaier.slugline.desktop" \
  "$NEXT_APPDIR/com.phagmaier.slugline.desktop"
install -Dm644 packaging/icons/com.phagmaier.slugline.svg \
  "$NEXT_APPDIR/com.phagmaier.slugline.svg"
ln -s com.phagmaier.slugline.svg "$NEXT_APPDIR/.DirIcon"

cat > "$NEXT_APPDIR/AppRun" <<'APPRUN'
#!/bin/sh
set -eu
appdir=${APPDIR:-$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)}
export LD_LIBRARY_PATH="$appdir/usr/lib/slugline/lib:$appdir/usr/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
export XDG_DATA_DIRS="$appdir/usr/share:${XDG_DATA_DIRS:-/usr/local/share:/usr/share}"
exec "$appdir/usr/lib/slugline/slugline" "$@"
APPRUN
chmod 755 "$NEXT_APPDIR/AppRun"

# Give linuxdeploy an ordinary writable home inside the packaging workspace.
# Neither this script nor the tool writes into the developer's real home.
export HOME="$WORK/home"
export XDG_CACHE_HOME="$WORK/cache"
export TMPDIR="$WORK/tmp"
# The Flutter/Rust release binaries are already stripped. Disabling
# linuxdeploy's extra strip pass also avoids old bundled binutils rejecting
# newer RELR sections when the script is run on a rolling distribution.
export NO_STRIP=1
# Metadata is validated separately with `appstreamcli --no-net`; appimagetool's
# built-in validator attempts URL reachability checks, which would make an
# otherwise offline packaging step depend on the network.
export LDAI_NO_APPSTREAM=1
mkdir -p "$HOME" "$XDG_CACHE_HOME" "$TMPDIR"

if file "$DEPLOY_TOOL" | grep -q 'AppImage'; then
  # New appimagetool builds otherwise fetch a runtime during assembly. Reuse
  # the already checksum-verified runtime header from the pinned linuxdeploy
  # AppImage, keeping this packaging step entirely offline.
  RUNTIME_SIZE="$("$DEPLOY_TOOL" --appimage-offset)"
  case "$RUNTIME_SIZE" in
    ''|*[!0-9]*) echo "Could not determine linuxdeploy AppImage runtime size." >&2; exit 1 ;;
  esac
  LDAI_RUNTIME_FILE="$WORK/runtime-x86_64"
  dd if="$DEPLOY_TOOL" of="$LDAI_RUNTIME_FILE" bs=1 count="$RUNTIME_SIZE" status=none
  export LDAI_RUNTIME_FILE
elif [ -z "${LDAI_RUNTIME_FILE:-}" ]; then
  echo "A native linuxdeploy requires LDAI_RUNTIME_FILE to avoid network access." >&2
  exit 2
fi

DEPLOY_ARGS=(
  --appdir "$NEXT_APPDIR"
  --executable "$NEXT_APPDIR/usr/lib/slugline/slugline"
  --library "$NEXT_APPDIR/usr/lib/slugline/lib/libflutter_linux_gtk.so"
  --library "$NEXT_APPDIR/usr/lib/slugline/lib/libslugline_bridge.so"
)
if file "$DEPLOY_TOOL" | grep -q 'AppImage'; then
  "$DEPLOY_TOOL" --appimage-extract-and-run "${DEPLOY_ARGS[@]}"
else
  "$DEPLOY_TOOL" "${DEPLOY_ARGS[@]}"
fi

# linuxdeploy installs a duplicate launcher while discovering its dependencies;
# the AppRun above intentionally starts Flutter beside its data/ and lib/
# directories, so the duplicate is unnecessary and could invite the wrong path.
rm -f "$NEXT_APPDIR/usr/bin/slugline"

rm -rf -- "$APPDIR"
mv "$NEXT_APPDIR" "$APPDIR"

echo "==> Creating $(basename "$OUT")"
rm -f -- "$OUT"
(
  cd "$ROOT/dist"
  export LINUXDEPLOY_OUTPUT_VERSION="$VERSION"
  if file "$DEPLOY_TOOL" | grep -q 'AppImage'; then
    "$DEPLOY_TOOL" --appimage-extract-and-run --appdir "$APPDIR" --output appimage
  else
    "$DEPLOY_TOOL" --appdir "$APPDIR" --output appimage
  fi
)

GENERATED="$ROOT/dist/Slugline-$VERSION-x86_64.AppImage"
[ -f "$GENERATED" ] || {
  echo "linuxdeploy did not create $(basename "$GENERATED")" >&2
  exit 1
}
chmod 755 "$GENERATED"
printf '%s\n' "$GENERATED"
