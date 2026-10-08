#!/usr/bin/env bash
# Run the local release gates and build both public artifacts.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

VERSION="$("$ROOT/tools/release_version.sh")"
echo "==> Slugline $VERSION release preflight"

for tool in cargo flutter python3 desktop-file-validate appstreamcli xvfb-run xdotool; do
  command -v "$tool" >/dev/null 2>&1 || {
    echo "Required preflight tool is missing: $tool" >&2
    exit 2
  }
done

python3 tools/check_version.py
python3 tools/check_layering.py
python3 tools/check_docs.py
python3 tools/make_reference.py --check
cargo fmt --all --check
cargo clippy --workspace --all-targets -- -D warnings
cargo test --workspace

(
  cd app
  flutter pub get
  dart format --output=none --set-exit-if-changed lib test integration_test test_driver
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
xvfb-run -a python3 tools/check_runtime_budgets.py --output target/runtime-budgets.json
xvfb-run -a python3 tools/check_clean_close.py --output target/clean-close.json
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

echo "Release preflight passed for v$VERSION."
