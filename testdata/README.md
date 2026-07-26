# Test data

`corpus/` holds the round-trip fixtures §4.3 asks for. Every one of them, and
every truncation of every one of them, must satisfy `serialise(parse(f)) == f`
byte for byte — see `crates/fountain/tests/roundtrip_is_byte_exact.rs` and
ADR 0007.

| File | §4.3 | What it is there to break |
| --- | --- | --- |
| `01-minimal.fountain` | 1 | One scene, one line of dialogue |
| `02-every-element.fountain` | 2 | One of each of the thirteen element kinds |
| `03-dual-dialogue.fountain` | 3 | `^` cues, with parentheticals on both sides |
| `04-notes-and-boneyard.fountain` | 4 | Notes and boneyard: multi-line, adjacent, inline, and one left unterminated |
| `05-title-page.fountain` | 5 | Every title-page field, multi-line values, an unknown key |
| `06-crlf.fountain` | 6 | Windows line endings throughout |
| `07-bom.fountain` | 7 | A UTF-8 BOM |
| `08-non-ascii.fountain` | 8 | Accents, CJK, an emoji, and a `@`-forced CJK cue |
| `09-whitespace.fountain` | 9 | Trailing spaces, leading tabs, a "blank" line that holds a tab |
| `10-malformed.fountain` | 10 | Truncated mid-word with no final newline; unterminated note; bare markers |
| `../reference-feature.fountain` | 11 | The 120-page feature, and the fixture for every §1.3 budget |

`reference-feature.fountain` is **generated**, not written:

```sh
python3 tools/make_reference.py            # regenerate
python3 tools/make_reference.py --check    # CI: fail if the committed file is stale
```

`golden/` holds expected layout dumps and PDF hashes, and is populated from
Phase 6 onward.

`line-breaking.json` is **generated**, not written. It is the wrap
`layout::line_spans` produces for every block above, for every rule in
`docs/LINE_BREAKING.md`, and for the reference feature, and it is what the
editor's `wrapText` is held to in `app/test/editor/line_break_differential_test.dart`:

```sh
# regenerate; without the variable the same test only checks the committed file
UPDATE_LINE_BREAK_FIXTURES=1 cargo test -p slugline_layout --test line_break_differential
```

Files here are inputs to tests and are compared byte-for-byte. Do not reformat
them, and do not let an editor strip trailing whitespace — several of them exist
precisely because of the whitespace they contain.
