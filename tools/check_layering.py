#!/usr/bin/env python3
"""Enforce the crate layering rule of spec §2.5.

    fountain    depends on nothing in the workspace
    document    depends only on fountain
    layout      depends only on document
    render_pdf  depends only on layout
    storage     depends only on document
    spell       depends on nothing in the workspace
    bridge      depends on everything

Run from anywhere:  python3 tools/check_layering.py

This is a script rather than a `cargo-deny` config because the rule we care
about is "who may depend on whom *inside* the workspace", which cargo-deny's
ban list expresses only clumsily, and because a wrong answer here is a design
error worth an explicit message. It uses only the standard library, so CI needs
nothing installed beyond Python and cargo.
"""

from __future__ import annotations

import json
import subprocess
import sys
from pathlib import Path

PREFIX = "screenplay_"

# crate -> the workspace crates it is allowed to depend on, directly or otherwise.
ALLOWED: dict[str, set[str]] = {
    "fountain": set(),
    "document": {"fountain"},
    "layout": {"document", "fountain"},
    "render_pdf": {"layout", "document", "fountain"},
    "storage": {"document", "fountain"},
    "spell": set(),
    "bridge": {"fountain", "document", "layout", "render_pdf", "storage", "spell"},
}

# The direct edges we expect. Anything else is either an upward dependency or a
# shortcut that skips a layer, and both deserve a conversation before they land.
EXPECTED_DIRECT: dict[str, set[str]] = {
    "fountain": set(),
    "document": {"fountain"},
    "layout": {"document"},
    "render_pdf": {"layout"},
    "storage": {"document"},
    "spell": set(),
    "bridge": set(),  # Phase 0: the bridge has no core crates wired in yet.
}


def short(name: str) -> str:
    return name[len(PREFIX):] if name.startswith(PREFIX) else name


def main() -> int:
    root = Path(__file__).resolve().parent.parent
    raw = subprocess.run(
        ["cargo", "metadata", "--format-version", "1", "--no-deps"],
        cwd=root,
        capture_output=True,
        text=True,
        check=True,
    ).stdout
    metadata = json.loads(raw)

    packages = {p["name"]: p for p in metadata["packages"]}
    members = {short(name) for name in packages}

    errors: list[str] = []

    missing = set(ALLOWED) - members
    unknown = members - set(ALLOWED)
    if missing:
        errors.append(f"workspace is missing crates: {sorted(missing)}")
    if unknown:
        errors.append(
            f"crates not covered by the layering rule: {sorted(unknown)} "
            "— add them to tools/check_layering.py and to §2.5"
        )

    for name, package in sorted(packages.items()):
        crate = short(name)
        if crate not in ALLOWED:
            continue
        deps = {
            short(d["name"])
            for d in package["dependencies"]
            if d["name"].startswith(PREFIX)
        }
        for dep in sorted(deps - ALLOWED[crate]):
            errors.append(
                f"{crate} -> {dep} violates §2.5 "
                f"(allowed: {sorted(ALLOWED[crate]) or 'nothing'})"
            )
        unexpected = deps - EXPECTED_DIRECT[crate] - ALLOWED[crate]
        for dep in sorted(unexpected):
            errors.append(f"{crate} -> {dep} is not an expected direct edge")

    if errors:
        print("Layering check failed (spec §2.5):", file=sys.stderr)
        for error in errors:
            print(f"  - {error}", file=sys.stderr)
        return 1

    print(f"Layering OK — {len(members)} crates, no upward dependencies.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
