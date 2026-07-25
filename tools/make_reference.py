#!/usr/bin/env python3
"""Generate `testdata/reference-feature.fountain`.

The reference script is the fixture for every performance budget in §1.3: a
120-page feature of roughly 19,000 words. It is generated rather than written so
that it is reproducible — the same script comes out of every machine, and a
diff to it is a deliberate change rather than a merge accident.

    python3 tools/make_reference.py            # write the file
    python3 tools/make_reference.py --check    # fail if the file is out of date

Randomness is a 32-bit LCG defined here rather than `random`, so the output does
not move when the Python version does. The page estimate uses the §5.2 metrics
(60 columns of action, 35 of dialogue, 54 lines a page); the authoritative
pagination arrives with the layout crate in Phase 6, and this estimate exists
only to keep the file near 120 pages.
"""

from __future__ import annotations

import argparse
import sys
import textwrap
from pathlib import Path

TARGET_PAGES = 120
LINES_PER_PAGE = 54
ACTION_COLUMNS = 60
DIALOGUE_COLUMNS = 35

OUTPUT = Path(__file__).resolve().parent.parent / "testdata" / "reference-feature.fountain"


class Lcg:
    """The numerical recipes LCG. Deterministic, tiny, and good enough to pick
    words out of a list."""

    def __init__(self, seed: int) -> None:
        self.state = seed & 0xFFFFFFFF

    def next(self) -> int:
        self.state = (1664525 * self.state + 1013904223) & 0xFFFFFFFF
        return self.state

    def below(self, limit: int) -> int:
        return self.next() % limit

    def pick(self, items: list[str]) -> str:
        return items[self.below(len(items))]


INTERIORS = [
    "KITCHEN", "STUDY", "HALLWAY", "GARAGE", "BEDROOM", "STAIRWELL", "OFFICE",
    "WAITING ROOM", "LIBRARY", "CORRIDOR", "BASEMENT", "ATTIC", "CAR",
    "TRAIN CARRIAGE", "LIFT", "PUB", "CHURCH HALL", "SURGERY", "CLASSROOM",
]
EXTERIORS = [
    "BECKWITH ROAD", "ALLOTMENTS", "CAR PARK", "CANAL PATH", "PLAYING FIELD",
    "BUS STOP", "CHURCHYARD", "PIER", "MOTORWAY BRIDGE", "GARDEN",
    "HIGH STREET", "RAILWAY EMBANKMENT",
]
TIMES = ["DAY", "NIGHT", "MORNING", "LATER", "CONTINUOUS", "DUSK", "DAWN", "EVENING"]
CHARACTERS = [
    "MARTHA", "DEREK", "PRIYA", "COLM", "ROSE", "IAN", "NADIA", "GEORGE",
    "SAM", "ELEANOR", "TOMÁS", "BRIDGET", "OWEN", "FRANCES",
]
EXTENSIONS = ["", "", "", "", " (V.O.)", " (O.S.)", " (CONT'D)"]
PARENTHETICALS = [
    "quietly", "not looking up", "after a moment", "flatly", "to himself",
    "to herself", "overlapping", "with the door still open", "already leaving",
]
TRANSITIONS = ["CUT TO:", "SMASH CUT TO:", "DISSOLVE TO:", "MATCH CUT TO:"]

NOUNS = [
    "kettle", "letter", "window", "coat", "engine", "hallway", "receipt",
    "photograph", "suitcase", "bicycle", "envelope", "cigarette", "doorway",
    "kitchen table", "answering machine", "carrier bag", "hospital band",
    "weather", "silence", "afternoon", "argument", "bus timetable", "kettle lid",
    "car keys", "front step", "washing line", "tin of paint", "unopened post",
]
VERBS = [
    "waits", "turns", "considers", "puts down", "picks up", "watches",
    "ignores", "counts", "folds", "unfolds", "abandons", "reaches for",
    "listens to", "steps around", "reads", "sets down", "straightens",
]
ADJECTIVES = [
    "cold", "half-finished", "borrowed", "expensive", "unopened", "familiar",
    "wrong", "second-hand", "unlit", "patient", "reluctant", "quiet",
]
CONNECTIVES = [
    "and then", "before", "long after", "while", "as if", "just as",
    "without looking at", "instead of",
]
DIALOGUE_OPENERS = [
    "You said", "I told you", "Nobody asked", "It's not about", "We agreed on",
    "Look at", "Give me", "There's no point in", "I'm not doing", "That was",
    "Ask her about", "You never mention", "I kept", "Put down",
]
DIALOGUE_TAILS = [
    "and you know it", "the same as always", "for once", "if you like",
    "before it gets dark", "the way you promised", "in front of everyone",
    "and I let you", "because nobody else would", "at half past six",
]


def sentence(rng: Lcg) -> str:
    who = rng.pick(CHARACTERS).title()
    return (
        f"{who} {rng.pick(VERBS)} the {rng.pick(ADJECTIVES)} {rng.pick(NOUNS)} "
        f"{rng.pick(CONNECTIVES)} the {rng.pick(NOUNS)}."
    )


def speech(rng: Lcg) -> str:
    return (
        f"{rng.pick(DIALOGUE_OPENERS)} the {rng.pick(NOUNS)}, "
        f"{rng.pick(DIALOGUE_TAILS)}."
    )


def wrap(text: str, columns: int) -> list[str]:
    return textwrap.wrap(text, columns) or [""]


class Script:
    """Accumulates Fountain source and an estimate of how many pages it is."""

    def __init__(self) -> None:
        self.parts: list[str] = []
        self.lines = 0
        self.words = 0

    def element(self, text: str, columns: int, blank_before: int) -> None:
        self.parts.append(text)
        self.lines += len(wrap(text.strip(), columns)) + blank_before
        self.words += len(text.split())

    def scene_heading(self, text: str) -> None:
        self.element(text, ACTION_COLUMNS, 2)

    def action(self, text: str) -> None:
        self.element(text, ACTION_COLUMNS, 1)

    def character(self, text: str) -> None:
        self.element(text, ACTION_COLUMNS, 1)

    def parenthetical(self, text: str) -> None:
        self.element(text, DIALOGUE_COLUMNS, 0)

    def dialogue(self, text: str) -> None:
        self.element(text, DIALOGUE_COLUMNS, 0)

    @property
    def pages(self) -> float:
        return self.lines / LINES_PER_PAGE


def build() -> tuple[str, Script]:
    rng = Lcg(20260724)
    script = Script()

    header = (
        "Title:\n"
        "   _**THE LONG WAY ROUND**_\n"
        "Credit: Written by\n"
        "Author: Slugline Test Fixture\n"
        "Source: Generated by tools/make_reference.py\n"
        "Draft date: 24 July 2026\n"
        "Notes:\n"
        "   The reference feature for the §1.3 performance budgets.\n"
        "   Regenerate with tools/make_reference.py; do not hand-edit.\n"
    )

    body: list[str] = []
    scene = 0
    while script.pages < TARGET_PAGES:
        scene += 1
        if scene % 3 == 0:
            place = f"EXT. {rng.pick(EXTERIORS)}"
        else:
            place = f"INT. {rng.pick(INTERIORS)}"
        heading = f"{place} - {rng.pick(TIMES)}"
        script.scene_heading(heading)
        body.append(heading)

        if scene % 17 == 0:
            section = f"# Part {scene // 17 + 1}"
            body.insert(len(body) - 1, section)
            body.insert(len(body) - 1, "")
            script.element(section, ACTION_COLUMNS, 1)

        for _ in range(1 + rng.below(3)):
            paragraph = " ".join(sentence(rng) for _ in range(1 + rng.below(3)))
            script.action(paragraph)
            body.append("")
            body.append(paragraph)

        for _ in range(2 + rng.below(4)):
            name = rng.pick(CHARACTERS) + rng.pick(EXTENSIONS)
            script.character(name)
            body.append("")
            body.append(name)
            if rng.below(4) == 0:
                note = f"({rng.pick(PARENTHETICALS)})"
                script.parenthetical(note)
                body.append(note)
            for _ in range(1 + rng.below(2)):
                line = speech(rng)
                script.dialogue(line)
                body.append(line)

        if scene % 7 == 0:
            transition = rng.pick(TRANSITIONS)
            script.element(transition, ACTION_COLUMNS, 1)
            body.append("")
            body.append(transition)

        body.append("")

    text = header + "\n" + "\n".join(body).rstrip("\n") + "\n"
    return text, script


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--check",
        action="store_true",
        help="exit non-zero if the committed file differs from the generated one",
    )
    args = parser.parse_args()

    text, script = build()
    if args.check:
        current = OUTPUT.read_text(encoding="utf-8") if OUTPUT.exists() else ""
        if current != text:
            print(f"{OUTPUT} is out of date; run tools/make_reference.py", file=sys.stderr)
            return 1
        print(f"{OUTPUT.name} is up to date.")
        return 0

    OUTPUT.write_text(text, encoding="utf-8")
    print(
        f"{OUTPUT.name}: {len(text.encode('utf-8')):,} bytes, "
        f"{script.words:,} words, ~{script.pages:.0f} pages"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
