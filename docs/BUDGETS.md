# Performance budgets

The thresholds this application is held to, what measures each one, and what
nothing measures yet. These are acceptance thresholds rather than aspirations: a
change that breaks one is a regression, and the number inside the test is the
contract.

The budgets were written in `SPEC.md` §1.3 at the start of the build. That table
is now provenance — it lives in a retired document, and it never carried the
parse or serialise rows at all — so **this file is the live list**. Change a
threshold by changing the test and this table together, and say in the commit
message whether the change was deliberate.

Every figure is for `testdata/reference-feature.fountain`, the 120-page
reference script.

| Budget | Metric | Measured by |
| --- | --- | --- |
| < 250 ms | Open the reference script → editable | `app/integration_test/keystroke_benchmark_test.dart` (`openBudgetMs`) |
| < 16 ms | Keystroke → core and back, p99 | same file (`keystrokeBudgetMs`), first assertion |
| < 16 ms | Keystroke → glyph on screen, p99 | same file, frame build time |
| < 100 ms | Parse the reference script | `crates/fountain/tests/parse_is_fast_enough.rs` |
| < 100 ms | Serialise it back out (save) | same file, second assertion |
| < 5 ms | Incremental repagination after one keystroke | `crates/layout/tests/pagination_is_fast_enough.rs` |
| < 50 ms | Full repagination, 120 pages | same file |
| < 1000 ms | PDF export, 120 pages | `crates/render_pdf/tests/export_is_fast_enough.rs` |
| < 60 MB | Stripped release binary + bundle | `.github/workflows/ci.yml`, "Check bundle size budget" |
| **< 500 ms** | **Cold start → blinking cursor, empty script** | **nothing** |
| **0%** | **Idle CPU, focused, no input** | **nothing** |
| **< 250 MB** | **RSS with the reference script open** | **nothing** |

**Debug builds relax some of these on purpose.** `cargo test` runs unoptimised,
so `pagination_is_fast_enough.rs` allows 100 ms full and 12 ms incremental under
`debug_assertions` while keeping the release figures above as the contract;
`parse_is_fast_enough.rs` holds 100 ms in both, because the release figure is
~0.44 ms. The keystroke budget measures frame **build** time, not wall clock:
wall clock is quantised to vsync, so 16.7 ms on a 60 Hz display is the floor
rather than a cost. ADR 0005 chose this editor's design on exactly that
measurement.

## The three nothing measures

Cold start, idle CPU and RSS are the budgets a writer feels most directly — a
slow launch, a fan, an editor that eats memory — and they are the three with no
test. They want one harness, which is why they are one backlog item
([F9](BACKLOG.md)): launch the release bundle from
`app/build/linux/x64/release/bundle`, time it to the first rendered frame, read
`/proc/<pid>/status` for RSS, and sample `/proc/<pid>/stat` over a quiet
interval for CPU.

Do not add a row here without the test that fails when it is exceeded. A budget
nobody measures is a claim, not a threshold.

## Running them

```sh
cargo test -p slugline_fountain --test parse_is_fast_enough
cargo test -p slugline_layout --test pagination_is_fast_enough   # --release for the table's figures
cargo test -p slugline_render_pdf --test export_is_fast_enough
./tools/test_linux_integration.sh                               # includes the keystroke benchmark
```

The layout and export budgets relax in a debug build, so `cargo test` gates on a
gross regression rather than the number above; `--release` measures the table.
ADR 0022 records the repagination budgets and ADR 0005 the editor measurements.
