# `slugline-bin` AUR package

This directory is the upstream-maintained AUR recipe for Slugline's prebuilt
Linux x86_64 release tarball. It installs the bundle directly; it does not call
the interactive upstream installer, use `sudo`, write to `$HOME`, or access the
network during `package()`.

`prepare()` verifies the tarball against the exact entry in the versioned
GitHub Release `SHA256SUMS` file. `makepkg` performs both downloads before any
build function runs.

## Validate a released version

From this directory on Arch Linux:

```sh
bash -n PKGBUILD
makepkg --verifysource
makepkg -sf
namcap PKGBUILD
namcap slugline-bin-*.pkg.tar.zst
makepkg --printsrcinfo | diff -u .SRCINFO -
```

For stronger isolation, run the same build with the `devtools` package:

```sh
extra-x86_64-build
```

## Publish or update the AUR package

An AUR account with an uploaded SSH key is required. Do not publish from this
upstream repository. Clone the AUR package repository separately:

```sh
git clone ssh://aur@aur.archlinux.org/slugline-bin.git ../../../../aur-slugline-bin
install -m644 PKGBUILD .SRCINFO ../../../../aur-slugline-bin/
cd ../../../../aur-slugline-bin
git add PKGBUILD .SRCINFO
git commit -m "Update to 1.0.0"
git push
```

For a later release, update `pkgver`, reset `pkgrel` to `1`, regenerate
`.SRCINFO` with `makepkg --printsrcinfo`, rerun every validation above, and then
commit and push the AUR repository. A `pkgrel` bump without a new upstream
version is only for changes to the Arch packaging itself.
