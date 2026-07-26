# Shared Line-Breaking Contract

**Status:** normative for `layout::break_lines` and the editor's `wrapText`
**Decision:** ADR 0018
**Scope:** soft wrapping inside one block; pagination rules are explicitly out of scope

This is the one line-breaking specification Rust pagination and the fluid Dart
editor must implement. The implementations may use different
offset encodings and result types, but the observable boundaries defined here
must agree.

## Input And Columns

- Input is document text with line endings normalized to `\n`. A carriage return
  is not part of the shared input domain.
- A width smaller than one is treated as one column.
- One Unicode scalar value occupies one column. This is deliberately neither a
  UTF-8 byte count, a UTF-16 code-unit count, nor a grapheme count.
- An astral-plane scalar such as `🎬` occupies one column even though Dart stores
  it as a surrogate pair. A combining sequence occupies one column per scalar;
  East Asian width and font shaping do not change the count.
- Caret movement and deletion may still use grapheme boundaries. That editor
  safety rule does not affect wrap columns.

## Text Preparation

Tabs are expanded before soft wrapping. A tab advances to the next four-column
stop measured from the start of its hard line: columns 0, 4, 8, and so on. A
hard newline resets the tab column; a soft wrap does not. The resulting spaces
participate in wrapping exactly like source ASCII spaces.

Scene headings, character cues, and transitions use locale-independent Unicode
uppercase for display. The transformed block is used only when every source
scalar maps to exactly one uppercase scalar with the same UTF-16 width. If any
scalar expands or otherwise changes offset width, the whole block is displayed
and wrapped as written. Thus `é` may become `É`, while a block containing `ß`
is not transformed to a block containing `SS`. This keeps every display boundary
mapped one-to-one to a source boundary.

Fountain emphasis markers are not preparation syntax here. `*`, `_`, and every
other visible marker remain ordinary scalars and each occupies one column.

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
2. Otherwise inspect the first `width + 1` scalars. If the scalar immediately
   after the width is a space, break at the width.
3. Otherwise break at the rightmost space inside the width, provided some
   non-space content precedes that space in the suffix.
4. If there is no eligible space, split exactly at the width. This is the only
   way a non-space run is split.
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
- a soft-wrap space run is the gap between the preceding line's end and the
  following line's start;
- a newline is excluded from both printable spans and terminates the preceding
  line; the source offset after it starts the next hard line;
- virtual spaces created by a tab carry the tab's source identity. A soft break
  inside that expansion is reported around the indivisible source tab: its
  fitted cells may be trailing display whitespace, while the tab remains in the
  consumed source gap and no offset points inside it;
- uppercase display scalars retain the source scalar's identity.

Dart stores these offsets as UTF-16 code units and Rust may store byte offsets.
The differential test normalizes both to source Unicode-scalar indices before
comparison. Different native numbers are not a semantic difference.

## Required Agreement

Given the same normalized source text, width, and uppercase-display flag, Dart
and Rust must agree on:

- visual-line count and hard-line boundaries;
- canonical source start, end, consumed-whitespace, and newline boundaries;
- display column count after tab expansion;
- every rule above for spaces, trailing spaces, empty lines, Unicode, uppercase,
  and literal emphasis markers.

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
