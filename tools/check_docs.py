#!/usr/bin/env python3
"""Assert that the documents an agent works from still describe this repository.

    python3 tools/check_docs.py

Run from anywhere. Exits non-zero on the first class of problem it finds.

Everything else in this repository is held to the code by something that
fails: the release version by `check_version.py`, the crate layering by
`check_layering.py`, the parser by the tiling test, the PDF by its hashes. The
prose had nothing, and prose is what an agent reads before it reads the code —
so a doc that describes a file that has moved, an ADR that has been superseded
without saying so, or a checklist item ticked without a result, is a defect
that nothing was catching.

Seven checks, each one a mistake that had actually happened in this tree:

1. Every repository path named in `AGENTS.md` exists. The guide's whole value is
   that its pointers are good.
2. Every `ADR NNNN` reference in any document resolves to a record.
3. Every relative markdown link resolves, and every in-file `#anchor` exists.
4. `docs/DECISIONS.md`'s index and its records agree about which records are
   live. A record that is dead in one place and live in the other is the trap
   the index exists to remove.
5. Supersession runs both ways. If a record says "Superseded by ADR 0014", then
   0014's header has to name it back — otherwise the log lies in one direction
   and an agent reading the wrong end implements the dead decision.
6. `docs/BACKLOG.md`'s checklist and its item sections are the same list, and a
   ticked box has a filled `Result` line.
7. A blocked item and its blocker agree, in both places and at both ends. The
   backlog's first rule is "take the first unticked item that is not blocked",
   which only means anything while "blocked" is a notation that cannot drift:
   the item says `**Blocked by XN.**` and `— *blocked by XN*`, and XN says
   `— *unblocks XN*` back.

Results may reference a commit subject or state that work is uncommitted.
Completion is about the requested behavior and relevant checks, not a hash.
"""

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

# The documents that are allowed to reference each other and the code. Missing
# files are a problem, so each is checked for existence as it is read.
DOCS = [
    "AGENTS.md",
    "README.md",
    "CHANGELOG.md",
    "CONTRIBUTING.md",
    "SECURITY.md",
    "docs/archive/SPEC.md",
    "docs/archive/REVIEW.md",
    "docs/ARCHITECTURE.md",
    *(str(path.relative_to(ROOT)) for path in sorted(ROOT.glob("crates/*/AGENTS.md"))),
    "app/AGENTS.md",
    "docs/BACKLOG.md",
    "docs/BUDGETS.md",
    "docs/DECISIONS.md",
    "docs/DEPENDENCIES.md",
    "docs/KEYMAP.md",
    "docs/LINE_BREAKING.md",
    "docs/MANUAL_GATES.md",
    "docs/RELEASING.md",
]

ROOT_FILES = {name for name in DOCS if "/" not in name}

# Retired documents. Frozen provenance: their links describe the tree as it
# was when they were retired, so links are never repaired and therefore never
# checked. Existence and ADR references still are.
ARCHIVED = {
    "docs/archive/SPEC.md",
    "docs/archive/REVIEW.md",
}

PATH_ROOTS = (
    "crates/",
    "app/",
    "docs/",
    "tools/",
    "testdata/",
    "packaging/",
    "spike/",
    "fuzz/",
    ".github/",
)

problems: list[str] = []
warnings: list[str] = []


def fail(where: str, message: str) -> None:
    problems.append(f"{where}: {message}")


def read(relative: str) -> str:
    path = ROOT / relative
    if not path.exists():
        fail(relative, "document does not exist")
        return ""
    return path.read_text(encoding="utf-8")


def anchor_of(heading: str) -> str:
    """GitHub's heading-to-anchor rule, close enough for our own headings."""
    text = heading.strip().lower()
    text = re.sub(r"[^\w\s-]", "", text)
    return re.sub(r"\s+", "-", text)


def links_and_anchors(name: str, text: str) -> None:
    base = Path(name).parent
    ids = set(re.findall(r'<a id="([^"]+)"', text))
    headings = set()
    for heading in re.findall(r"^#{2,4} (.+)$", text, re.M):
        headings.add(anchor_of(heading))

    for match in re.finditer(r"\]\(([^)\s]+)\)", text):
        target = match.group(1)
        line = text[: match.start()].count("\n") + 1
        if target.startswith(("http://", "https://", "mailto:")):
            continue
        if target.startswith("#"):
            if target[1:] not in ids and target[1:] not in headings:
                fail(f"{name}:{line}", f"anchor #{target[1:]} does not exist")
            continue
        path = (base / target.split("#")[0]).resolve()
        if not path.exists():
            fail(f"{name}:{line}", f"link target {target} does not exist")


def adr_references(name: str, text: str, known: set[int]) -> None:
    for match in re.finditer(r"ADR\s+(\d{4})", text):
        if int(match.group(1)) not in known:
            line = text[: match.start()].count("\n") + 1
            fail(f"{name}:{line}", f"ADR {match.group(1)} does not exist")


def paths_in_agents(text: str) -> None:
    for match in re.finditer(r"`([^`\n]+)`", text):
        candidate = match.group(1).strip()
        if not (candidate in ROOT_FILES or candidate.startswith(PATH_ROOTS)):
            continue
        # Placeholders and globs are instructions, not pointers.
        if any(ch in candidate for ch in "*<>{}"):
            continue
        if not (ROOT / candidate).exists():
            line = text[: match.start()].count("\n") + 1
            fail(f"AGENTS.md:{line}", f"path {candidate} does not exist")


def records(text: str) -> dict[str, dict]:
    """Split DECISIONS.md into its records, keeping each header block."""
    found: dict[str, dict] = {}
    order = re.findall(r"^## ADR (\d{4}) — (.+)$", text, re.M)
    if not order:
        fail("docs/DECISIONS.md", "no records found")
        return found
    for index, (number, title) in enumerate(order):
        start = text.index(f"## ADR {number} — ")
        end = text.find("\n## ADR ", start + 1)
        body = text[start : end if end != -1 else len(text)]
        header = body.split("\n### ", 1)[0]
        found[number] = {"title": title, "body": body, "header": header}
    return found


def index_status(text: str) -> dict[str, str]:
    """The `Status` column of the index table, keyed by record number."""
    if "## Index" not in text:
        fail("docs/DECISIONS.md", "the index is missing")
        return {}
    table = text.split("## Index", 1)[1].split("\n---\n", 1)[0]
    status = {}
    for line in table.split("\n"):
        match = re.match(r"^\| (\d{4}) \|", line)
        if match:
            cells = [cell.strip() for cell in line.strip("|").split("|")]
            status[match.group(1)] = cells[-1] if cells else ""
    return status


def field(header: str, name: str) -> str | None:
    """The value of a `**Name:**` header field, up to the next field or the end."""
    match = re.search(
        r"\*\*" + name + r":\*\*(.*?)(?=\n\*\*[A-Z]|\Z)", header, re.S
    )
    return match.group(1).strip() if match else None


def supersession(found: dict[str, dict]) -> None:
    """Annotations and relation fields must agree, in both directions."""
    annotated: dict[str, str] = {}
    for number, record in found.items():
        header = record["header"]
        if field(header, "Superseded by"):
            annotated[number] = "superseded"
        elif field(header, "Historical"):
            annotated[number] = "historical"

    # Forward: an annotation must name a record that names it back.
    for number, kind in annotated.items():
        if kind == "historical":
            continue
        declared = field(found[number]["header"], "Superseded by") or ""
        named = re.findall(r"ADR\s+(\d{4})", declared)
        if not named:
            fail(f"ADR {number}", "a 'Superseded by' line names no record")
            continue
        for reference in named:
            if reference not in found:
                fail(f"ADR {number}", f"superseded by ADR {reference}, which does not exist")
                continue
            newer = found[reference]["header"]
            relation = None
            for name in ("Supersedes", "Narrows", "Refines", "Extends"):
                value = field(newer, name)
                if value:
                    relation = (name, value)
                    break
            if not relation:
                fail(
                    f"ADR {reference}",
                    f"ADR {number} says it was superseded by this record, "
                    "but this record declares no relation to it",
                )
            elif number not in re.findall(r"\d{4}", relation[1]):
                fail(
                    f"ADR {reference}",
                    f"its {relation[0]} line does not name ADR {number}",
                )

    # Backward: a record named by a newer one must carry an annotation — unless
    # the relation is additive. `Extends` says "this record adds to that one";
    # `Supersedes`, `Narrows` and `Refines` all say part of the older record no
    # longer governs, which is exactly what a reader has to be told.
    displacing = ("Supersedes", "Narrows", "Refines")
    for number, record in found.items():
        relation = None
        for name in ("Supersedes", "Narrows", "Refines", "Extends"):
            value = field(record["header"], name)
            if value:
                relation = (name, value)
                break
        if not relation:
            continue
        # "Supersedes: nothing; it states a sequence ADR 0013 left implicit"
        # mentions a record without claiming to replace it.
        if relation[1].lower().startswith("nothing"):
            continue
        if relation[0] not in displacing:
            continue
        for older in re.findall(r"ADR\s+(\d{4})", relation[1]):
            if older not in found:
                fail(f"ADR {number}", f"names ADR {older}, which does not exist")
            elif older not in annotated:
                fail(
                    f"ADR {older}",
                    f"ADR {number} declares {relation[0]} of it, "
                    "but it carries no 'Superseded by' or 'Historical' line",
                )

    # The index and the records must agree about who is live.
    status = index_status(read("docs/DECISIONS.md"))
    if status:
        for number in found:
            if number not in status:
                fail("docs/DECISIONS.md", f"ADR {number} is missing from the index")
                continue
            live = status[number] == "live"
            if live and number in annotated:
                fail(
                    f"ADR {number}",
                    f"is '{annotated[number]}' in its record but 'live' in the index",
                )
            if not live and number not in annotated:
                fail(
                    f"ADR {number}",
                    f"is '{status[number]}' in the index but carries no annotation",
                )


def backlog(text: str) -> None:
    checklist = re.findall(r"^- \[([ x])\] \[([A-Z]+\d+)\]\(#([a-z0-9-]+)\)", text, re.M)
    if not checklist:
        fail("docs/BACKLOG.md", "no checklist entries found")
        return

    anchors = set(re.findall(r'<a id="([^"]+)"></a>', text))
    sections = set(re.findall(r"^### ([A-Z]+\d+) — ", text, re.M))
    results = {}
    for match in re.finditer(r"^### ([A-Z]+\d+) — .*?(?=^### |\Z)", text, re.M | re.S):
        item, body = match.group(1), match.group(0)
        if "**Result:**" in body:
            result = body.split("**Result:**", 1)[1].split("\n\n")[0].strip()
            if not result:
                fail("docs/BACKLOG.md", f"{item} has an empty Result; use _open_ until complete")
            results[item] = bool(result) and "_open_" not in result

    seen = set()
    for ticked, item, anchor in checklist:
        seen.add(item)
        if anchor not in anchors:
            fail("docs/BACKLOG.md", f"{item}'s checklist anchor #{anchor} has no target")
        if item not in sections:
            fail("docs/BACKLOG.md", f"{item} is in the checklist but has no section")
        if item not in results:
            fail("docs/BACKLOG.md", f"{item} has no Result line")
            continue
        if (ticked == "x") != results[item]:
            state = "ticked" if ticked == "x" else "unticked"
            other = "filled in" if results[item] else "_open_"
            fail("docs/BACKLOG.md", f"{item} is {state} but its Result is {other}")

    for item in sections:
        if item not in seen:
            fail("docs/BACKLOG.md", f"{item} has a section but is not in the checklist")


def blocks(text: str) -> None:
    """A blocked item, its blocker, and both places each is written.

    The backlog's first rule is "take the first unticked item that is not
    blocked". Before this, "blocked" was an italic aside on one item and the
    rule said nothing about it, so a literal reading walked straight into F7 —
    which cannot be done until X6, twenty items further down, is finished.
    """
    declared: dict[str, str] = {}
    for match in re.finditer(r"^### ([A-Z]+\d+) — .*?(?=^### |\Z)", text, re.M | re.S):
        blocker = re.search(r"\*\*Blocked by ([A-Z]+\d+)\.\*\*", match.group(0))
        if blocker:
            declared[match.group(1)] = blocker.group(1)

    notes: dict[str, str] = {}
    unblocks: dict[str, list[str]] = {}
    ticked: dict[str, bool] = {}
    for match in re.finditer(
        r"^- \[([ x])\] \[([A-Z]+\d+)\]\(#[a-z0-9-]+\)(.*)$", text, re.M
    ):
        done, item, rest = match.group(1) == "x", match.group(2), match.group(3)
        ticked[item] = done
        note = re.search(r"\*blocked by ([A-Z]+\d+)\*", rest)
        if note:
            notes[item] = note.group(1)
        unblocks[item] = re.findall(r"\*unblocks ([A-Z]+\d+)\*", rest)

    for item, blocker in declared.items():
        if blocker not in ticked:
            fail("docs/BACKLOG.md", f"{item} is blocked by {blocker}, which is not an item")
            continue
        if ticked[item]:
            fail("docs/BACKLOG.md", f"{item} is ticked and still says it is blocked by {blocker}")
        if item not in notes:
            fail(
                "docs/BACKLOG.md",
                f"{item}'s section says 'Blocked by {blocker}' but its checklist line does not",
            )
        elif notes[item] != blocker:
            fail(
                "docs/BACKLOG.md",
                f"{item}'s checklist says blocked by {notes[item]}, its section says {blocker}",
            )
        if item not in unblocks.get(blocker, []):
            fail(
                "docs/BACKLOG.md",
                f"{item} waits on {blocker}, so {blocker}'s checklist line needs '— *unblocks {item}*'",
            )
        if ticked.get(blocker):
            warnings.append(
                f"{item} is still marked blocked by {blocker}, which is done — "
                "unblock it or point it at what it is really waiting for"
            )

    for item, blocker in notes.items():
        if item not in declared:
            fail(
                "docs/BACKLOG.md",
                f"{item}'s checklist says blocked by {blocker} but its section does not",
            )
    for item, others in unblocks.items():
        for other in others:
            if other not in declared:
                fail(
                    "docs/BACKLOG.md",
                    f"{item} says it unblocks {other}, which is not marked blocked by it",
                )


def main() -> None:
    texts = {name: read(name) for name in DOCS}
    decisions = texts["docs/DECISIONS.md"]
    known = {int(number) for number in re.findall(r"^## ADR (\d{4})", decisions, re.M)}

    for name, text in texts.items():
        if not text:
            continue
        if name not in ARCHIVED:
            links_and_anchors(name, text)
        adr_references(name, text, known)

    paths_in_agents(texts["AGENTS.md"])
    found = records(decisions)
    if found:
        supersession(found)
    backlog(texts["docs/BACKLOG.md"])
    blocks(texts["docs/BACKLOG.md"])

    for warning in warnings:
        print(f"warning: {warning}", file=sys.stderr)
    if problems:
        for problem in problems:
            print(f"  {problem}", file=sys.stderr)
        print(f"\nDocs check failed: {len(problems)} problem(s).", file=sys.stderr)
        sys.exit(1)

    print(
        f"Docs OK — {len(texts)} documents, {len(known)} ADRs, "
        f"{len(re.findall(r'^- \[[ x]\] \[', texts['docs/BACKLOG.md'], re.M))} backlog items."
    )


if __name__ == "__main__":
    main()
