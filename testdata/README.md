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

## Independent FDX producer

`fdx/fade-in-5.0.15.fdx` was exported on 2026-10-09 by the official
[Fade In 5.0.15 Linux demo](https://www.fadeinpro.com/page.pl?content=download),
run from an isolated `/tmp` directory/profile, without installation. Its
screenplay/title text is self-authored for Slugline: `Interchange Trial`,
`Agent Fixture`, the numbered import-room scene, styled Unicode Action,
ALICE/BOB dual speeches, a transition, page break, centered ending and script
note. It is not copied from a third-party screenplay or an AGPL fixture.

The file is the producer's complete, unmodified output, including its standard
layout/title settings. SHA-256:
`7374c4dcf133e40bd4cf0aec0edd315d20a5cdb2860bf3da34ece4186ed7ba5a`.
The actual producer surface and source input are retained under
`target/x2-fdx-smoke/`. Its Fountain import did not export the input's outline
section/synopsis to FDX; tests assert the actual FDX, not missing producer data.
Its literal `/* omitted text */` is visible Action in FDX, not a hidden boneyard.
The codec/native tests exercise this producer profile; Slugline self-round trips
alone do not establish compatibility.

