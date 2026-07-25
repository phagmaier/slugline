# Test data

Empty until Phase 1, when the parser lands. Spec §4.3 lists what
`corpus/` must contain before Phase 1 can exit:

1. A minimal script (one scene, one line of dialogue)
2. Every element type, one of each
3. Dual dialogue
4. Nested and adjacent notes and boneyard comments
5. A title page with all fields, including multi-line values
6. A file using Windows line endings
7. A file with a UTF-8 BOM
8. A file with non-ASCII names (accents, CJK)
9. A file with unusual-but-valid whitespace (trailing spaces, tabs)
10. A malformed/truncated file
11. The 120-page reference feature (`reference-feature.fountain`, ~19,000 words),
    which is also the fixture for every performance budget in §1.3

`golden/` holds expected layout dumps and PDF hashes, and is populated from
Phase 5 onward.

Files here are inputs to tests and are compared byte-for-byte. Do not reformat
them, and do not let an editor strip trailing whitespace — several of them exist
precisely because of the whitespace they contain.
