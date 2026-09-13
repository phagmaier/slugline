# Releasing Slugline

`app/pubspec.yaml` owns the public release version. `Cargo.toml`, AppStream
metadata, and `CHANGELOG.md` repeat it where their formats require a copy.
`tools/check_version.py` checks the application copies.

The supported release target is Linux x86_64. GitHub Actions builds on Ubuntu
24.04 with Flutter 3.44.8 (pinned as `flutter-version` in the workflows;
`app/pubspec.yaml` declares the minimum supported SDK) and stable Rust.

## One-time repository settings

No personal access token or repository secret is needed. The release workflow
uses the built-in `GITHUB_TOKEN`.

In **Settings → Actions → General**:

1. Allow the actions used by the repository: `actions/checkout`,
   `dtolnay/rust-toolchain`, `Swatinem/rust-cache`, and
   `subosito/flutter-action` (or allow all actions).
2. Under **Workflow permissions**, allow **Read and write permissions**. The
   workflow also narrows its declaration to `contents: write`.

If an organization policy prevents write-capable workflow tokens, an
organization owner must permit `contents: write`; adding a PAT is not the
preferred workaround.

For private security reports, also enable **Settings → Security → Code security
and analysis → Private vulnerability reporting**.

## Local prerequisites

Install the development dependencies listed in `README.md`, plus `xvfb`,
`desktop-file-utils`, `appstream`, and preferably `shellcheck`. The preflight
fails when Xvfb is unavailable and reports explicitly when optional ShellCheck
is unavailable.

AppImages are assembled with this pinned linuxdeploy release:

```sh
release_tools_dir="$(mktemp -d)"
curl -fsSL \
  -o "$release_tools_dir/linuxdeploy-x86_64.AppImage" \
  https://github.com/linuxdeploy/linuxdeploy/releases/download/1-alpha-20251107-1/linuxdeploy-x86_64.AppImage
printf '%s  %s\n' \
  c20cd71e3a4e3b80c3483cef793cda3f4e990aca14014d23c544ca3ce1270b4d \
  "$release_tools_dir/linuxdeploy-x86_64.AppImage" |
  sha256sum -c -
chmod 755 "$release_tools_dir/linuxdeploy-x86_64.AppImage"
export LINUXDEPLOY="$release_tools_dir/linuxdeploy-x86_64.AppImage"
```

`tools/make_appimage.sh` does not download anything. It reuses the verified
linuxdeploy AppImage's type-2 runtime header so AppImage assembly stays offline.

## Human release workflow

1. Start from a clean, current `main`:

   ```sh
   git switch main
   git pull --ff-only
   git status --short
   ```

2. Update `app/pubspec.yaml`, `Cargo.toml`, the newest release in
   `packaging/com.phagmaier.slugline.metainfo.xml`, and `CHANGELOG.md`:

   ```sh
   python3 tools/check_version.py
   ```

3. Run the complete local verification and artifact build:

   ```sh
   LINUXDEPLOY="$LINUXDEPLOY" ./tools/release_preflight.sh
   ```

   This runs Rust formatting, Clippy and tests; version, layering and reference
   checks; Flutter analysis, unit tests and all Linux integration tests under
   Xvfb; metadata and shell checks; the offline gate; both artifact builds and
   smoke tests; and checksum generation. The real 4 MB full-disk test remains a
   CI gate because mounting its tmpfs is intentionally not done by local tools.

4. Review and commit the release changes:

   ```sh
   git diff --check
   git status --short
   git add -A
   git commit -m "Release $(tools/release_version.sh)"
   ```

5. Create and inspect the annotated tag. The helper refuses a dirty tree and
   never pushes:

   ```sh
   ./tools/create_release_tag.sh
   git show "v$(tools/release_version.sh)"
   ```

6. Push the commit and tag explicitly:

   ```sh
   git push origin main
   git push origin "v$(tools/release_version.sh)"
   ```

7. Watch the **Release** workflow. A failed required step prevents publication.
   A rerun for the same tag is safe: it recreates only this tag's three named
   assets with `--clobber`. It never targets “latest” or a differently tagged
   release.

8. Verify the published files:

   ```sh
   release_version="$(tools/release_version.sh)"
   verify_dir="$(mktemp -d)"
   gh release download "v$release_version" --dir "$verify_dir"
   cd "$verify_dir"
   sha256sum -c SHA256SUMS
   "./Slugline-$release_version-x86_64.AppImage" --version
   "./Slugline-$release_version-x86_64.AppImage" --help
   ```

The GitHub push is the only unavoidable authenticated account-level action.

## What a pushed version tag does

For `v<version>`, `.github/workflows/release.yml` verifies that the tag exactly
matches `app/pubspec.yaml`, installs the supported toolchains and dependencies,
runs every required repository and GUI integration gate, builds and smoke-tests
`slugline-<version>-linux-x86_64.tar.gz` and
`Slugline-<version>-x86_64.AppImage`, writes and checks `SHA256SUMS`, and only
then creates or updates the GitHub Release for that exact tag.

The tarball's archive metadata is normalized, and Rust source paths are
remapped. The AppImage includes the Flutter/Rust bundle and linuxdeploy's
discoverable GTK runtime dependencies. Neither packaging script uses `sudo`,
writes to the developer's home directory, or downloads a tool.

## Manual desktop checks

Before announcing a release broadly, run the AppImage and installed tarball on
a real desktop and check opening a `.fountain` file from the file manager,
Wayland and X11 startup, HiDPI/fractional scaling, an `ibus` CJK input method,
PDF viewing/printing, and at least one non-Arch distribution. These checks are
not represented as automated passes.
