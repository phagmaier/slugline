#!/usr/bin/env bash
# Run the local release gates and build both public artifacts.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

VERSION="$("$ROOT/tools/release_version.sh")"
echo "==> Slugline $VERSION release preflight"

for tool in cargo flutter python3 desktop-file-validate appstreamcli xvfb-run; do
  command -v "$tool" >/dev/null 2>&1 || {
    echo "Required preflight tool is missing: $tool" >&2
    exit 2
  }
done

python3 tools/check_version.py
python3 tools/check_layering.py
python3 tools/make_reference.py --check
cargo fmt --all --check
cargo clippy --workspace --all-targets -- -D warnings
cargo test --workspace

(
  cd app
  flutter pub get
  flutter analyze
  flutter test
)
"$ROOT/tools/test_linux_integration.sh"

desktop-file-validate packaging/com.phagmaier.slugline.desktop
appstreamcli validate --no-net packaging/com.phagmaier.slugline.metainfo.xml
bash -n tools/*.sh
if command -v shellcheck >/dev/null 2>&1; then
  shellcheck tools/*.sh
else
  echo "NOTICE: shellcheck is unavailable locally; the release workflow requires it."
fi

tools/package.sh
tools/check_no_network.sh
tools/smoke_test_tarball.sh
tools/make_appimage.sh
tools/smoke_test_appimage.sh

(
  cd dist
  sha256sum \
    "slugline-$VERSION-linux-x86_64.tar.gz" \
    "Slugline-$VERSION-x86_64.AppImage" > SHA256SUMS
  sha256sum -c SHA256SUMS
)

(
  cd packaging/aur/slugline-bin
  bash -n PKGBUILD
  if command -v makepkg >/dev/null 2>&1; then
    diff -u .SRCINFO <(makepkg --printsrcinfo)
  fi
)

if command -v makepkg >/dev/null 2>&1; then
  AUR_WORK="$(mktemp -d)"
  trap 'rm -rf "$AUR_WORK"' EXIT
  mkdir -p "$AUR_WORK/build" "$AUR_WORK/packages"
  (
    cd packaging/aur/slugline-bin
    SRCDEST="$ROOT/dist" \
      BUILDDIR="$AUR_WORK/build" \
      PKGDEST="$AUR_WORK/packages" \
      makepkg --force --noconfirm
  )
  if command -v namcap >/dev/null 2>&1; then
    namcap packaging/aur/slugline-bin/PKGBUILD
    namcap "$AUR_WORK"/packages/slugline-bin-*.pkg.tar.zst
  else
    echo "NOTICE: namcap is unavailable locally; run it before the AUR push."
  fi
else
  echo "NOTICE: makepkg is unavailable; AUR build validation requires Arch Linux."
fi

echo "Release preflight passed for v$VERSION."
