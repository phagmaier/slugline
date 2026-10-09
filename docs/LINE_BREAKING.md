# Shared Line-Breaking Contract

**Status:** normative for `layout::break_lines` and the editor's `wrapText`
**Decision:** ADR 0018, refined by ADR 0057
**Scope:** soft wrapping inside one block; pagination rules are explicitly out of scope

This is the one line-breaking specification Rust pagination and the fluid Dart
editor must implement. The implementations may use different
offset encodings and result types, but the observable boundaries defined here
must agree.

## Input And Columns

- Input is document text with line endings normalized to `\n`. A carriage return
  is not part of the shared input domain.
- A width smaller than one is treated as one column.
- One printed Unicode scalar value occupies one column. Paired emphasis markers
  and escaping backslashes occupy zero printed columns, as resolved by Rust.
  This is deliberately neither a UTF-8 byte, UTF-16 unit nor grapheme count.
- An astral-plane scalar such as `🎬` occupies one column even though Dart stores
  it as a surrogate pair. A combining sequence occupies one column per scalar;
  East Asian width and font shaping do not change the count.
- Caret movement and deletion may still use grapheme boundaries. That editor
  safety rule does not affect wrap columns.

## Text Preparation

Tabs are expanded before soft wrapping, after removing zero-width syntax from
the printed projection. A tab advances to the next four-column stop measured
from the start of its hard line: columns 0, 4, 8, and so on. A hard newline
resets the tab column; a soft wrap does not. Expanded spaces wrap like ASCII spaces.

Scene headings, **unforced** character cues, and transitions use
locale-independent Unicode uppercase for display. A forced Character cue keeps
its author's exact case, including in dual lanes, resolved styled runs and
continuation names (ADR 0060). This rendering rule never edits source text or
reclassifies a block. When capitals are requested, the transformation is decided
**one scalar at a time**: a scalar is uppercased only when its uppercase is
exactly one scalar of the same UTF-16 width, and is otherwise displayed as
written. Thus `é` becomes `É`, while
`ß` stays `ß` rather than becoming `SS`, and `int. straße - tag` displays as
`INT. STRAßE - TAG`. This keeps every display boundary mapped one-to-one to a
source boundary, so uppercasing can never move a wrap.

Per scalar rather than per block is a deliberate choice: refusing a whole block
would show an entire scene heading in lower case because of one character.
Dart's `String.toUpperCase` already declines exactly the expanding scalars, so
the editor takes the whole-string path and verifies scalar alignment, while Rust
checks `char::to_uppercase` per scalar; the two agree character for character.

**A heading is shown in capitals.** Across the whole Latin range — ASCII,
Latin-1, and Latin Extended-A and B — the only letters this rule leaves in lower
case are `ß`, `ŉ`, and `ǰ`, the three whose capital is more than one scalar. A
test on each side pins that set, so nothing else can quietly join it.

**The capital itself is guaranteed through U+017F** — ASCII, Latin-1 and Latin
Extended-A, which is the alphabet an English screenplay is written in plus every
accented name, loan word and European spelling one plausibly carries. Inside
that range the editor and the paginator must show the same letter, and the
differential test fails if they do not.

Past it this document promises the wrap, not the glyph. Dart's
`String.toUpperCase` and Rust's `char::to_uppercase` are the same rule over
different vintages of the same Unicode tables, and today they part company on
`ƛ` (U+019B), `ȿ` (U+023F), `ɀ` (U+0240) and `ϳ` (U+03F3): Rust capitalises
them, the Dart SDK shows them as typed. Each is one scalar of the same UTF-16
width either way, so no column and no boundary moves, and the wrap is still
compared. A divergence out there that *would* change a width still fails, at any
code point — that is the offset guarantee this whole document exists for. Showing
those three as `SS`, `ʼN`, and `J̌` would mean a display string longer than the
model, which this document exists to prevent; it is possible — a column already
need not be a model offset, which is how tabs work — but it would also cost the
accessibility layer its guarantee that a selection offset means the same thing
in both strings, so it is not done for three letters.

Fountain's existing `emphasis` scanner owns the projection. Sparse source runs
identify paired markers/escaping slashes as hidden and carry resolved bold,
italic and underline flags; plain gaps are implied. Unpaired markers and
non-escaping backslashes remain ordinary printed scalars. The editor consumes
the runs from `BlockView.inline_runs` and edit patches, never parses markup and
never makes an additional keystroke bridge call. Plain text has empty metadata.

Body projection pairs across the block's explicit hard lines, with marker
eligibility treating each hard boundary as a space. In Dialogue the semantic
leading `~` is hidden before pairing and implies italic only on that sung hard
line; explicit inline emphasis may continue across hard lines. Title values
resolve each source hard line independently, before soft wrapping.

## Hard Lines

Every `\n` is a mandatory visual break and is not a printable column. Splitting
on `\n` preserves every segment, including empty leading, trailing, and
consecutive segments. Therefore empty text occupies one empty visual line,
`"\n"` occupies two, and `"one\n"` occupies a non-empty line followed by an
empty line.

Each hard-line segment is soft-wrapped independently after tab expansion.

## Soft Wrapping

Only ASCII space (`U+0020`) is a soft-wrap opportunity. For the unplaced suffix
of one hard line:

1. If it fits within the width, emit it unchanged, including its trailing
   spaces.
2. Otherwise inspect the first `width + 1` printed cells. If the cell immediately
   after the width is a space, break at the width.
3. Otherwise break at the rightmost space inside the width, provided some
   non-space printed content precedes that space in the suffix.
4. If there is no eligible space, split exactly at the printed width. This is the
   only way a non-space run is split; hidden syntax cannot create a marker-only wrap.
5. After a space break, consume the complete run of spaces beginning at that
   boundary before starting the next line. Internal spaces before the selected
   boundary remain visible.
6. If consuming boundary spaces exhausts a non-empty hard line, do not emit a
   phantom empty line.

Consequently `break("one two three", 7)` is `['one two', 'three']`, an
over-width word is split at column 7, and `break("abc ", 3)` is `['abc']`.

## Source Boundaries

The canonical result is an ordered list of half-open source spans plus an
optional terminating-hard-newline offset for each line. Spans refer to the
original, unexpanded, non-uppercased block text:

- no boundary may split a Unicode scalar;
- a soft-wrap visible space run is the gap between the preceding line's end and
  following start, except that hidden syntax in that gap belongs to the preceding
  source span and remains editable there; consumed visible spaces are not painted;
- a newline is excluded from both printable spans and terminates the preceding
  line; the source offset after it starts the next hard line;
- virtual spaces created by a tab carry the tab's source identity. A soft break
  inside that expansion is reported around the indivisible source tab: its
  fitted cells may be trailing display whitespace, while the tab remains in the
  consumed source gap and no offset points inside it;
- uppercase display scalars retain the source scalar's identity.
- hidden prefixes belong to the following printed cell (the first cell includes
  the hard-line start); trailing hidden syntax belongs to the final line;
- marker-only hard lines keep their entire source span and occupy zero printed
  columns, but still produce one visual row;
- source spans can include consumed spaces when needed to retain hidden markers.
  The retained printed-cell map, not the raw source substring, defines width.

## Editable Display Projection

The editor wraps on the printed map above. Separately, each hidden source scalar
occupies a dim half-cell at half font size in the editable display; all other
retained cells use their full printed advance. Markers have their own slots,
never an overlapping glyph overlay. An editable row can extend beyond its
printed measure because these slots do not alter wrapping or page/source anchors.
The sheet grid and row geometry remain unchanged. Horizontal scrolling exposes
overflowing editable rows, including every marker and the line-end caret; it
does not shrink the script or move printed wraps/page anchors.

`VisualLine.columns`, `columnAtOffset` and `offsetAtColumn` are the printed map.
`displayColumnAtOffset` and `offsetAtDisplayColumn` are the editable map. Painting,
pointer hits, vertical movement, caret, selection, find and composing/spelling
underlines use the latter. Every marker boundary remains individually clickable;
Unicode scalar boundaries remain exact and tabs indivisible. Clipboard, IME and
accessibility continue to receive the unchanged Fountain source and UTF-16
selections, not the compressed display string.

Dart stores these offsets as UTF-16 code units and Rust may store byte offsets.
The differential test normalizes both to source Unicode-scalar indices before
comparison. Different native numbers are not a semantic difference.

## Contextual Speech Widths

Ordinary cues, dialogue and parentheticals wrap at 33, 35 and 20 cells.
ADR 0054 gives both members of a dual pair cue/dialogue/parenthetical widths
of 20/28/20 cells. Pair adjacent Character-plus-body speeches greedily and
without overlap when the second cue carries `dual` and both bodies contain
Dialogue/Parenthetical blocks. Any other source block interrupts the pair.
An unmatched flag uses ordinary widths. Empty body text still occupies a row.

Rust applies those widths before caching wraps; the linear editor mirrors
only this wrapping context, not two-column placement or page breaks.
Membership changes invalidate unchanged partners' cached wraps. Both sides
retain per-block source-line indices for preview/page-position anchors.


## How This Is Enforced

`layout::line_spans` and `wrapText` return the canonical result above;
`layout::break_lines` is the same wrap rendered as strings, and shares its
implementation. Neither language runs the other, so the comparison is a
generated fixture:

- `crates/layout/tests/line_break_differential.rs` builds every case: the rules
  above at twelve widths, emphasis pairing/escape/sung boundaries, whole-Unicode
  casing sweeps, every block in `testdata/corpus/` as typed and as prepared, and
  every block of the 120-page reference feature. It fails unless
  `testdata/line-breaking.json` is exactly what this crate produces. Regenerate
  deliberately with `UPDATE_LINE_BREAK_FIXTURES=1 cargo test -p slugline_layout
  --test line_break_differential`.
- Every generated case includes sparse Rust-resolved runs in scalar indices.
  `app/test/editor/line_break_differential_test.dart` converts these exactly to
  UTF-16, supplies them to `wrapText` and compares boundaries, printed columns
  and newlines. Failures report the source, width and first mismatching row.

Both run in CI, in the Rust job and the Flutter job respectively. Changing this
document means changing both implementations and regenerating the fixture in one
commit; a wrap that changes on one side alone fails one of the two.

## Required Agreement

Given the same normalized source text, resolved inline projection, width and
uppercase-display flag, Dart and Rust must agree on:

- visual-line count and hard-line boundaries;
- canonical source start, end, consumed-whitespace, and newline boundaries;
- printed display column count after tab expansion;
- every rule above for spaces, trailing spaces, empty lines, Unicode, uppercase,
  paired/escaped syntax and unpaired literal markers.

The implementations need not return the same data type or materialize tab
spaces in the same string. Agreement is on boundaries and columns, not an
incidental representation.

## Allowed Differences

The editor is a continuous editing surface; pagination places already-wrapped
lines onto pages. The following are outside this shared contract and may differ:

- UTF-16 editor offsets versus UTF-8 Rust storage, and grapheme-aware caret,
  selection, hit-testing, and IME behavior;
- editor-only blocks and source text that paginated output deliberately omits,
  including sections, synopses, notes, and boneyards;
- block preprocessing such as printable-note removal and scene-number extraction;
  the primitive comparison supplies identical prepared text to both wrappers;
- indentation, alignment, blank rows between elements, page dimensions, and the
  reduced spacing used at the top of a page;
- explicit page breaks, widow/orphan rules, scene-heading and character-cue
  carries, dialogue splitting, `(MORE)` and `(CONT'D)`, title pages, page numbers,
  and fixed-point pagination.

None of those differences permits the editor and Rust to choose different soft
wrap boundaries for the same prepared text and width.
