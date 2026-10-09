# Dependencies

Spec §1.2: **every new dependency needs a one-line justification here.** Reject
anything that pulls a large transitive tree. Add the entry in the same commit
that adds the dependency; CI does not check this, reviewers do.

Format: `name` — what it does — why we cannot reasonably do without it.

## Verification tools

`xdotool` — observes the release process's first-frame X window and establishes
and checks input focus for F9's runtime budgets, and types into that window for
B16's clean-close check — avoids adding a production benchmark marker or a
window-manager dependency; installed only on test hosts.

`gdb` — attempts bounded all-thread native stacks only after a release startup
deadline fails — live blocked-thread evidence cannot be reconstructed after
cleanup; installed only on test hosts, and unavailable/denied attachment remains
diagnostic evidence rather than a new harness prerequisite.

## Rust crates

| Crate | Version | Used by | Justification |
| --- | --- | --- | --- |
| `flutter_rust_bridge` | 2.12.0 | `bridge` | The FFI boundary itself (§2.2). Pinned with `=` because the Rust crate and the Dart package must agree exactly, or the generated glue is silently wrong. |
| `quick-xml` | 0.38.3 | `fdx` | Streaming XML events with no DTD/network resolution or default features; avoids an XML DOM/framework and adds only memchr at runtime (ADR 0055). |
| `proptest` (dev) | 1.11.0 | `fountain`, `document` | Phase 1's round-trip properties are the §13 testing strategy's own answer for "invariants a fixture cannot cover". It found the Opaque-block edit and the parenthetical-dialogue cases; both are now ADR 0007 text. Test-only, so it is absent from the shipped binary. |
| `criterion` (dev) | 0.5.1 | `fountain`, `layout` | Named in §13 for the §1.3 budgets. Taken with `default-features = false`, which drops `plotters` and its tree: we need the number, not the SVG. Test-only. |
| `libfuzzer-sys` (dev) | 0.4 | `fuzz/` | Phase 1 requires a `cargo-fuzz` target for the parser. Lives in `fuzz/`, which is a separate workspace on a nightly toolchain, so it is not in any build that CI or a user runs. |
| `serde` | 1.0.229 | `storage` | §2.6's choice for the files a user might have to look at. The journal is exactly such a file: when recovery goes wrong the writer's text is *in there* and they must be able to get it out with a text editor. Derives only — `document` and `fountain` stay free of it (ADR 0013). |
| `serde_json` | 1.0.151 | `storage` | The format itself, for the journal, the library index and the preferences. §2.6: "human-readable on disk, by design". |
| `directories` | 6.0.0 | `storage` | ADR 0006 settled `$XDG_*_HOME/slugline`; this is the one crate that knows the XDG rules and the fallbacks. Two transitive crates (`dirs-sys`, `option-ext`) plus `libc`. Hand-rolling it means hand-rolling the fallbacks, and getting one wrong puts a user's journal somewhere they will never find it. |
| `libc` | 0.2 (locked 0.2.189) | `storage` | Exclusive nonblocking `flock` on each journal inode protects live sessions and releases ownership on process death; already transitive, no new dependency tree, and avoids raising the workspace floor to 1.89 for `File::try_lock` (ADR 0042). |
| `notify` | 8.2.0 | `storage` | §2.6's choice, and §Phase 4's "`notify` watcher on open files". Taken with `default-features = false`, which drops the polling backend: a poller is a wakeup several times a second in a process §1.3 budgets at 0% idle CPU. The cost is that a script on NFS reports no external changes, which is a convenience, not a safety property. Its `notify-types` requires Rust 1.85, which is half of what sets the workspace's floor. |
| `spellbook` | 0.4.2 | `spell` | §2.6's pure-Rust Hunspell-compatible checker; it lets Slugline use the dictionaries Linux already ships without linking `libhunspell`, and carries only its hash-table implementation. Its `hashbrown` requires Rust 1.85, the other half of the workspace's floor. |

`printpdf`, the other original output shortlist candidate, was turned down when
Phase 7 reached it — see below.

Workspace edge `layout -> fountain` — reuse the existing emphasis pairing and
escape rules for printed-width alignment, without a second scanner or any new
external dependency (ADR 0044).

Workspace edge `bridge -> fountain` — name the existing emphasis-run type while
transporting the PDF's shared interpretation to the preview, without a document
re-export or a Dart scanner; no external dependency (ADR 0045).

Workspace edges `fdx -> fountain` and `bridge -> fdx` — convert interchange copies using the existing screenplay model and emphasis scanner without document/history ownership or a second native format (ADR 0055).

## Vendored assets

| Asset | Version | Used by | Justification |
| --- | --- | --- | --- |
| Courier Prime — Regular, Bold, Italic, Bold Italic | 1.203 | `render_pdf`, `app` | §Phase 7: "Courier Prime vendored and embedded, with the OFL licence file shipped in the bundle". Taken unmodified from the upstream release and `include_bytes!`d, because §1.2 rules out font downloads and a screenplay that renders differently because a system font moved is not one you can send anyone. 305 KB in the repository; a subset of about 30 KB in each export. The editor and the preview draw the script in the same four faces, declared in `app/pubspec.yaml` — `app/fonts/` holds **symlinks** into `crates/render_pdf/fonts/`, never copies, so the screen and the PDF cannot come to disagree about the face and the PDF goldens stay the one thing pinning it. No second download and no second 305 KB. |
| `OFL.txt` | SIL OFL 1.1 | `render_pdf` | The licence those four faces are under. `include_str!`d as well as shipped, so it cannot be dropped from a package without breaking the build. |

`tempfile` is deliberately absent: `storage`'s tests want `mkdir` and `rm -r`,
which is twenty-five lines in `storage/src/testing.rs`. `DEPENDENCIES.md` already
turns down `cargo-deny` on the same grounds.

## Dart packages

| Package | Version | Justification |
| --- | --- | --- |
| `flutter_rust_bridge` | 2.12.0 | Dart half of the bridge. Must match the Rust crate version. |
| `freezed_annotation` | 3.1.0 | Runtime annotations for the sealed classes FRB generates from Rust enums with fields. Required, not optional — see ADR 0003. |
| `freezed` (dev) | 3.2.5 | Code generator for the above. Runs during `flutter_rust_bridge_codegen generate`, never during `flutter build`. |
| `build_runner` (dev) | 2.15.1 | Drives `freezed`. Same story: codegen-time only. |
| `integration_test` (dev) | SDK | Runs the bridge proofs against the real `.so`. Ships with Flutter. |
| `characters` | 1.4.0 | Grapheme-cluster boundaries for caret motion and deletion. Without it, Backspace next to an emoji produces an offset inside a surrogate pair, which the bridge refuses outright (ADR 0001) — so the key would appear to do nothing. Dart-team package, no transitive dependencies, already in Flutter's own dependency set. |

## Deliberately not taken

| Rejected | Instead | Why |
| --- | --- | --- |
| `cargo-deny` | `tools/check_layering.py` | The rule we actually need is intra-workspace layering (§2.5), which cargo-deny expresses awkwardly. 60 lines of stdlib Python beats a config file plus a binary in CI. Revisit if we ever need licence or advisory auditing. |
| A separate core daemon + IPC | in-process `cdylib` | §2.2. |
| `tokio` | `std::thread` + Rayon later | The core has no I/O concurrency to speak of: one actor thread and a worker pool (§2.3). An async runtime would be pure weight. |
| `json_annotation` | — | Pulled in transitively by `freezed_annotation`; we do not use it directly. |
| `file_selector` / `file_selector_linux` | GTK 3 through `slugline/window` (`library/file_chooser.dart`, Linux runner) | The runner already links GTK; calling its local chooser directly adds no dependency or HTTP client. The selector package's transitive `http` remains unnecessary. ADR 0052 supersedes the old in-app chooser decision without weakening the zero-network requirement. |
| `intl` | `backups_dialog.dart` | One date format and one byte format, for a UI where "Today at 14:32" is the whole requirement. |
| `printpdf` (Rust) | `crates/render_pdf` | §2.6 shortlisted it and Phase 7 turned it down (ADR 0032). Everything §Phase 7 asks for beyond drawing text is a statement about bytes — a fixed `/ID`, a `SOURCE_DATE_EPOCH` timestamp, no hash-map iteration order, subsetting, a pinned SHA-256 — and those are properties of a writer, not of a drawing API. A large tree, its own subsetter, and a document id this crate would have to reach past it to fix, to write the easy half. |
| `sha2` / `sha1` (Rust) | `render_pdf::sha256` | Two callers — the document `/ID` and the golden test — and fifty lines of FIPS 180-4 with published vectors beside it. |
| `flate2` (Rust) | uncompressed PDF streams | Compressing the content streams would save perhaps 60% of 666 KB. Subsetting the font is where the weight actually was, and an uncompressed stream is one a person can read and one less place for output to vary. |
| `ttf-parser` / `allsorts` (Rust) | `render_pdf::sfnt` | Embedding a `CIDFontType2` needs six tables read and six written, from four files this repository ships and controls. A general-purpose parser is for fonts you did not choose. |
| `chrono` (Rust) | `storage::backup` | Backups are named by Unix milliseconds and retention buckets by `millis / 86_400_000`. No calendar arithmetic is needed anywhere, and the UI formats the date in Dart, where the locale is. |
