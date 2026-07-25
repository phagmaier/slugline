# Dependencies

Spec §1.2: **every new dependency needs a one-line justification here.** Reject
anything that pulls a large transitive tree. Add the entry in the same commit
that adds the dependency; CI does not check this, reviewers do.

Format: `name` — what it does — why we cannot reasonably do without it.

## Rust crates

| Crate | Version | Used by | Justification |
| --- | --- | --- | --- |
| `flutter_rust_bridge` | 2.12.0 | `bridge` | The FFI boundary itself (§2.2). Pinned with `=` because the Rust crate and the Dart package must agree exactly, or the generated glue is silently wrong. |
| `proptest` (dev) | 1.11.0 | `fountain`, `document` | Phase 1's round-trip properties are the §13 testing strategy's own answer for "invariants a fixture cannot cover". It found the Opaque-block edit and the parenthetical-dialogue cases; both are now ADR 0007 text. Test-only, so it is absent from the shipped binary. |
| `criterion` (dev) | 0.5.1 | `fountain` | Named in §13 for the §1.3 budgets. Taken with `default-features = false`, which drops `plotters` and its tree: we need the number, not the SVG. Test-only. |
| `libfuzzer-sys` (dev) | 0.4 | `fuzz/` | Phase 1 requires a `cargo-fuzz` target for the parser. Lives in `fuzz/`, which is a separate workspace on a nightly toolchain, so it is not in any build that CI or a user runs. |

Nothing else yet. The remaining crates from the §2.6 shortlist (`printpdf`,
`spellbook`, `directories`, `notify`, `serde`) are added in the phase that first
needs them, not before.

## Dart packages

| Package | Version | Justification |
| --- | --- | --- |
| `flutter_rust_bridge` | 2.12.0 | Dart half of the bridge. Must match the Rust crate version. |
| `freezed_annotation` | 3.1.0 | Runtime annotations for the sealed classes FRB generates from Rust enums with fields. Required, not optional — see ADR 0003. |
| `freezed` (dev) | 3.2.5 | Code generator for the above. Runs during `flutter_rust_bridge_codegen generate`, never during `flutter build`. |
| `build_runner` (dev) | 2.15.1 | Drives `freezed`. Same story: codegen-time only. |
| `integration_test` (dev) | SDK | Runs the bridge proofs against the real `.so`. Ships with Flutter. |

## Deliberately not taken

| Rejected | Instead | Why |
| --- | --- | --- |
| `cargo-deny` | `tools/check_layering.py` | The rule we actually need is intra-workspace layering (§2.5), which cargo-deny expresses awkwardly. 60 lines of stdlib Python beats a config file plus a binary in CI. Revisit if we ever need licence or advisory auditing. |
| A separate core daemon + IPC | in-process `cdylib` | §2.2. |
| `tokio` | `std::thread` + Rayon later | The core has no I/O concurrency to speak of: one actor thread and a worker pool (§2.3). An async runtime would be pure weight. |
| `json_annotation` | — | Pulled in transitively by `freezed_annotation`; we do not use it directly. |
