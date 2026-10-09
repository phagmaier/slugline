#!/usr/bin/env python3
"""Backlog helper with the same "blocked" reading as tools/check_docs.py.

    python3 tools/backlog.py next

Run from anywhere. Read-only: it never edits docs/BACKLOG.md.

`next` prints the first unticked checklist item that is not blocked, using
the backlog's own rule: an item is blocked when its section carries a
`**Blocked by XN.**` line *and* its checklist line says `*blocked by XN*`.
An item whose blocker is already ticked is reported as unblocked (check_docs
warns on those: the notation has gone stale and the item is workable).
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
BACKLOG = ROOT / "docs" / "BACKLOG.md"


def load() -> str:
    if not BACKLOG.exists():
        print(f"error: {BACKLOG} does not exist", file=sys.stderr)
        sys.exit(1)
    return BACKLOG.read_text(encoding="utf-8")


def parse(text: str):
    checklist: list[tuple[bool, str, str, str]] = []
    for match in re.finditer(
        r"^- \[([ x])\] \[([A-Z]+\d+)\]\(#([a-z0-9-]+)\)(.*)$", text, re.M
    ):
        done = match.group(1) == "x"
        checklist.append((done, match.group(2), match.group(3), match.group(4)))

    titles: dict[str, str] = {}
    for match in re.finditer(r"^### ([A-Z]+\d+) — (.+)$", text, re.M):
        titles[match.group(1)] = match.group(2).strip()

    declared: dict[str, str] = {}
    for match in re.finditer(r"^### ([A-Z]+\d+) — .*?(?=^### |\Z)", text, re.M | re.S):
        blocker = re.search(r"\*\*Blocked by ([A-Z]+\d+)\.\*\*", match.group(0))
        if blocker:
            declared[match.group(1)] = blocker.group(1)

    notes: dict[str, str] = {}
    for done, item, _anchor, rest in checklist:
        note = re.search(r"\*blocked by ([A-Z]+\d+)\*", rest)
        if note:
            notes[item] = note.group(1)

    ticked = {item: done for done, item, _a, _r in checklist}
    return checklist, titles, declared, notes, ticked


def is_blocked(item: str, declared, notes, ticked) -> str | None:
    """Return the blocker id, or None when the item is workable."""
    blocker = declared.get(item)
    if blocker is None:
        return None
    if notes.get(item) != blocker:
        # Notation drift; check_docs.py fails on this. Do not treat a
        # half-marked item as blocked: surface it instead.
        return None
    if ticked.get(blocker):
        # Blocker is done; the "blocked" mark is stale.
        return None
    return blocker


def cmd_next() -> int:
    text = load()
    checklist, titles, declared, notes, ticked = parse(text)
    if not checklist:
        print("error: no checklist entries found in docs/BACKLOG.md", file=sys.stderr)
        return 1
    skipped: list[str] = []
    for done, item, anchor, _rest in checklist:
        if done:
            continue
        blocker = is_blocked(item, declared, notes, ticked)
        if blocker is not None:
            skipped.append(f"{item} (blocked by {blocker})")
            continue
        title = titles.get(item, "")
        print(f"NEXT {item} — {title}" if title else f"NEXT {item}")
        print(f"Section: docs/BACKLOG.md#{anchor}")
        effort = re.search(
            rf"^### {re.escape(item)} — .*?\n\n\*\*Effort\.\*\* ([^\n]+)",
            text,
            re.M | re.S,
        )
        if effort:
            print(f"Effort: {effort.group(1).strip()}")
        if blocker is None and item in declared:
            print(f"Note: stale block mark resolved; {item} waited on {declared[item]}, which is done.")
        if skipped:
            print(f"Skipped blocked: {', '.join(skipped)}")
        print("Read the item; reproduce bugs, choose focused checks, and follow AGENTS.md's completion policy.")
        return 0
    print("No unticked, unblocked items. The backlog is clear or everything left is blocked.")
    if skipped:
        print(f"Blocked: {', '.join(skipped)}")
    return 0


def main(argv: list[str]) -> int:
    if argv == ["next"]:
        return cmd_next()
    print((__doc__ or "").strip())
    print("\nusage: python3 tools/backlog.py next")
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
