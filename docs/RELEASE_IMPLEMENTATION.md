# Release implementation note

## Current state

- `app/pubspec.yaml` is the release-version authority. The current release
  version is **1.0.0**; Cargo, AppStream metadata, and `CHANGELOG.md` agree.
- `.github/workflows/ci.yml` runs Rust formatting, Clippy, tests, layering,
  reference-fixture and version checks; Flutter analysis, unit tests, release
  build and seven Xvfb integration suites; metadata validation; the offline
  runtime gate; and basic tarball installation. It runs for `main`, pull
  requests, and manual dispatch.
- The Linux Flutter bundle contains the runner, Flutter ICU/assets/AOT/runtime,
  the Rust bridge shared library, and all four Courier Prime faces. The runner
  resolves bundled libraries through `$ORIGIN/lib`.
- `tools/package.sh` stages a release tree with desktop, AppStream, MIME, icon,
  GPL/OFL, documentation, installer, and uninstaller files.
- `tools/make_appimage.sh` creates an AppDir from that staged tree when an
  external `appimagetool` is already installed.
- There are no local version tags and no release-specific GitHub configuration.

## Problems found

- Passing CI cannot create a GitHub Release: there is no `v*` tag trigger,
  release job, `contents: write` permission, checksum generation, or GitHub
  Release API/CLI step. The tarball is only a temporary Actions artifact.
- The package job recompiles the same release independently and does not build
  or validate an AppImage.
- The tarball uses the ambiguous `x64` architecture spelling, preserves local
  ownership/timestamps, and has only a minimal install smoke test. It does not
  verify extraction safety, linkage, required payload files, uninstallation, or
  embedded build-machine paths.
- The current AppImage contains the Flutter/Rust bundle but does not deploy
  discoverable Linux runtime libraries, has no automated smoke test, and is not
  built in CI.
- The current Rust release bundle embeds the local repository path in the Rust
  shared library; release builds need a compiler path remap.
- The README still treats a source checkout as the normal installation route,
  calls Flatpak the primary distribution, contains a screenshot TODO and a
  duplicated screenshot reference, and has no public release/AUR instructions.
- There is no release guide, tag preflight helper, AUR definition, contribution
  or security guide, or GitHub issue templates.

## Files expected to change

- Packaging and validation: `tools/package.sh`, `tools/make_appimage.sh`, new
  artifact smoke tests and a release preflight/tag helper.
- Automation and documentation: a new tag-triggered workflow under
  `.github/workflows/`, `docs/RELEASING.md`, `README.md`, and this note.
- Distribution: new `packaging/aur/slugline-bin/` files.
- Public project support: `CHANGELOG.md`, `CONTRIBUTING.md`, `SECURITY.md`, and
  issue templates under `.github/ISSUE_TEMPLATE/`.
- Toolchain metadata only if needed to make the workflow use an explicit
  project-supported Flutter version.

## Release flow to implement

1. A developer runs one local preflight command, reviews a clean tree, and
   creates an annotated `v<pubspec-version>` tag without an automatic push.
2. Pushing that tag starts one release workflow with explicit `contents: write`
   permission and concurrency scoped to the tag.
3. The workflow verifies the tag/version match, installs the pinned Flutter
   toolchain plus stable Rust and Linux dependencies, and runs every required
   Rust, Flutter, integration, metadata, and offline gate before publication.
4. The already-verified release bundle is staged as
   `slugline-<version>-linux-x86_64.tar.gz`; linuxdeploy builds
   `Slugline-<version>-x86_64.AppImage`.
5. Both artifacts are extracted and smoke-tested, including CLI output,
   payload, linkage, desktop metadata, and build-path checks.
6. The workflow writes `SHA256SUMS`, then creates the release for the exact tag
   or replaces only those three assets on a safe rerun.
7. The prepared `slugline-bin` AUR recipe downloads the versioned tarball,
   verifies its checksum, and installs its payload directly into Arch package
   paths. Publishing to GitHub and the AUR remains an authenticated,
   account-level action.
