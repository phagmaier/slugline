# fdx — scoped agent notes

Scope: pure FDX screenplay interchange (`fdx -> fountain`), not native file
persistence, history, layout or production-revision fidelity (ADR 0055).

`src/lib.rs` owns secure streaming recognition and deterministic UTF-8 emission;
`src/styles.rs` adapts Text runs through Fountain's shared emphasis scanner.

- Never resolve a DTD/custom entity, fetch resources or guess an encoding.
- Every unsupported textual structure is preserved with a warning or refused
  before an operation changes live content. Whitespace and hard lines are text.
- Nonprinting Fountain kinds export as visible Action text with explicit recipient
  visibility warnings. Kind plus literal Text restores nonprinting semantics only
  in Slugline. `SluglineRaw` is limited to inline hidden semantics/unrepresentable
  canonical span pairing and must agree with actual Text/styles/scene numbers.
  All semantic metadata must agree with the visible paragraph kind, alignment
  and page-break flag; stale metadata must not hide externally edited content.
- Title fields use standard positional paragraphs plus `SluglineTitleField`;
  unmatched external title text is retained in Notes with a warning.
  Repeated keys coalesce with hard lines before entering the native title form,
  which edits one value per key. Title emphasis pairs independently per hard
  line, unlike body/dialogue emphasis across wraps.
- Only real adjacent, disjoint ADR 0054 speech pairs gain DualDialogue wrappers.
- Standard finite ParagraphSpec bounds make emitted paragraphs visible in other
  consumers. They are interchange defaults, not a copy of Slugline's pagination
  or a claim of font/margin fidelity.
- Authored ScriptNote/header/footer text is retained in nonprinting Notes with
  placement warnings; custom headers/footers are labeled. SmartType completion
  caches and dynamic Page # punctuation are layout/settings, excluded with
  diagnostics rather than manufactured screenplay notes. Unknown authored
  textual shapes refuse; literal XML `[[` refuses if it would become hidden.
- Imports normalize empty Action spacers and adjacent Dialogue boundaries, then
  validate canonical Fountain kind/text/dual identity order for save/reopen.
  Recovery initialization is the bridge/storage owner's full semantic patch.

Verification follows the [root policy](../../AGENTS.md#verification): run the
relevant `cargo test -p slugline_fdx` filter or test target; the whole crate only
when warranted. Run `python3 tools/check_layering.py` when dependency edges
change. No fixture implies producer provenance, and self-roundtrip tests are not
independent consumer verification. Release/package checks wait for the final
release task. Update these notes only when their invariants or pointers change.
