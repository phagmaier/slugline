#!/usr/bin/env python3
"""Assert that everything that names a release version names the same one.

    app/pubspec.yaml    version: 1.0.0+1     <- the source of truth
    Cargo.toml          version = "1.0.0"
    packaging/*.metainfo.xml  <release version="1.0.0" .../>
    CHANGELOG.md        ## 1.0.0 - ...

Run from anywhere:  python3 tools/check_version.py

§Phase 11 asks for one release-version source. There cannot literally be one
file — Cargo will not read pubspec and AppStream will not read Cargo — so there
is one *authority* and a check that the copies agree. The application's version
is the one a user sees in `--version` and in their software centre, so
`pubspec.yaml` is the authority and everything else is a copy that this script
keeps honest.

The build number after the `+` is Flutter's and is deliberately not compared:
it exists to be bumped without changing the release, which is exactly what a
rebuild of the same version is.
"""

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def fail(message: str) -> None:
    print(f"Version check failed: {message}", file=sys.stderr)
    sys.exit(1)


def read(relative: str) -> str:
    path = ROOT / relative
    if not path.exists():
        fail(f"{relative} does not exist")
    return path.read_text(encoding="utf-8")


def search(pattern: str, text: str, what: str) -> str:
    found = re.search(pattern, text, re.MULTILINE)
    if not found:
        fail(f"no version found in {what}")
    return found.group(1)


def main() -> None:
    # The authority. `1.0.0+1` -> `1.0.0`; the build number is not a release.
    release = search(r"^version:\s*([0-9]+\.[0-9]+\.[0-9]+)", read("app/pubspec.yaml"), "app/pubspec.yaml")

    copies = {
        "Cargo.toml": search(
            r'^version = "([0-9]+\.[0-9]+\.[0-9]+)"',
            read("Cargo.toml"),
            "Cargo.toml [workspace.package]",
        ),
        "packaging/com.phagmaier.slugline.metainfo.xml": search(
            r'<release version="([0-9]+\.[0-9]+\.[0-9]+)"',
            read("packaging/com.phagmaier.slugline.metainfo.xml"),
            "the AppStream metainfo",
        ),
        "CHANGELOG.md": search(
            r"^## ([0-9]+\.[0-9]+\.[0-9]+)",
            read("CHANGELOG.md"),
            "the changelog's newest entry",
        ),
    }

    wrong = {name: found for name, found in copies.items() if found != release}
    if wrong:
        for name, found in wrong.items():
            print(f"  {name}: {found}  (app/pubspec.yaml says {release})", file=sys.stderr)
        fail("these disagree with app/pubspec.yaml")

    # Every workspace crate takes the workspace version rather than declaring
    # one. `slugline_bridge` pinned its own at 0.1.0 and went on reporting it
    # long after the workspace moved, which is how the release ended up with two
    # answers in the first place.
    pinned = []
    for manifest in sorted((ROOT / "crates").glob("*/Cargo.toml")):
        text = manifest.read_text(encoding="utf-8")
        if not re.search(r"^version\.workspace = true", text, re.MULTILINE):
            own = re.search(r'^version = "([^"]+)"', text, re.MULTILINE)
            pinned.append(f"  crates/{manifest.parent.name}: {own.group(1) if own else 'no version'}")
    if pinned:
        print("\n".join(pinned), file=sys.stderr)
        fail("these crates pin a version instead of using `version.workspace = true`")

    print(f"Version OK — {release}, in pubspec.yaml and {len(copies)} copies, "
          f"and every crate takes the workspace's.")


if __name__ == "__main__":
    main()
