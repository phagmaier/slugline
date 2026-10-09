# Performance budgets

The thresholds this application is held to, what measures each one, and what
nothing measures yet. These are acceptance thresholds rather than aspirations: a
change that breaks one is a regression, and the number inside the test is the
contract.

The budgets were written in `docs/archive/SPEC.md` §1.3 at the start of the build. That table
is now provenance — it lives in a retired document, and it never carried the
parse or serialise rows at all — so **this file is the live list**. Change a
threshold by changing the test and this table together, and say in the commit
message whether the change was deliberate.

Every script-size figure is for `testdata/reference-feature.fountain`, the
120-page reference script. Startup instead names an empty script. Memory
figures use MiB (1024 × 1024 bytes), as the existing bundle-size check does.

| Budget | Metric | Measured by |
| --- | --- | --- |
| < 250 ms | Open the reference script → editable | `app/integration_test/keystroke_benchmark_test.dart` (`openBudgetMs`) |
| < 16 ms | Keystroke → core and back, p99, before using Find and after closing it with a retained query | same file (`keystrokeBudgetMs`), first assertion |
| < 16 ms | Keystroke → glyph on screen, p99, same two Find states | same file, frame build time on the same isolated editing surface |
| < 16 ms | Journalled keystroke → core and back, p99, same two Find states | same file, crash-journal benchmark |
| < 100 ms | Parse the reference script | `crates/fountain/tests/parse_is_fast_enough.rs` |
| < 100 ms | Serialise it back out (save) | same file, second assertion |
| < 5 ms | Incremental repagination after one keystroke | `crates/layout/tests/pagination_is_fast_enough.rs` |
| < 50 ms | Full repagination, 120 pages | same file |
| < 1000 ms | PDF export, 120 pages | `crates/render_pdf/tests/export_is_fast_enough.rs` |
| < 60 MB | Stripped release binary + bundle | `.github/workflows/ci.yml`, "Check bundle size budget" |
| < 500 ms | Fresh process → first-frame window, empty script argument; best of 5 | `tools/check_runtime_budgets.py` (`STARTUP_MS`) |
| 0 ticks and 0 voluntary thread switches | Focused idle, 10 s after measured quiet; best of 3 | same file (`IDLE_SECONDS`) |
| < 320 MiB | RSS with the reference open, Xvfb / llvmpipe, `LP_NUM_THREADS=4`; best of 3 | same file (`XVFB_RSS_MIB`) |
| < 250 MiB | RSS with the reference open on a real GPU desktop; best of 3 | same file, `--desktop` (`DESKTOP_RSS_MIB`); [manual gate 5](MANUAL_GATES.md#5-real-desktop-runtime-budgets) |

**Debug builds relax some of these on purpose.** `cargo test` runs unoptimised,
so `pagination_is_fast_enough.rs` allows 100 ms full and 12 ms incremental under
`debug_assertions` while keeping the release figures above as the contract;
`parse_is_fast_enough.rs` holds 100 ms in both, because the release figure is
~0.44 ms. The keystroke budget measures frame **build** time, not wall clock:
wall clock is quantised to vsync, so 16.7 ms on a 60 Hz display is the floor
rather than a cost. ADR 0005 chose this editor's design on exactly that
measurement.

## Release-process measurements

[F9](BACKLOG.md#f9) and ADR 0050 add one harness over the shipped bundle at
`app/build/linux/x64/release/bundle`, with no production timing marker. The GTK
runner maps the window on Flutter's first frame; `xdotool search --onlyvisible
--pid` observes that event. Timing starts immediately before spawning the process
and includes fork/exec, a query and up to 5 ms between queries. It does not prove
an editable caret: script adoption runs after the first frame. A fresh
no-argument launch shows the library, so startup passes a zero-byte managed Fountain
fixture and separately confirms that the requested file was opened and journalled.
The editor's caret is static; “blinking cursor” was historical wording. Fresh
processes and XDG directories do not evict the OS file cache. The best of five
retains the 500 ms limit while rejecting sustained delays rather than the worst
shared-runner scheduling event; all five values are printed and retained.

RSS comes from `VmRSS` in `/proc/<pid>/status`, CPU ticks from `utime + stime`
in `/proc/<pid>/stat`, and voluntary context switches from every thread's
`/proc/<pid>/task/<tid>/status`. CPU ticks alone can miss a lightweight poller.
Two consecutive seconds with no ticks, switches or changed thread set establish
quiet; failure to settle within 60 seconds fails. Each idle interval is ten
seconds, with X input focus established and checked at both ends. The best of
three consecutive intervals in one process must have zero ticks and switches
in at least one interval. Restarting for every sample can repeat the same late
engine-thread cleanup phase, so intervals advance through time instead. This
allows the existing 30-second status-age refresh to fall outside one interval;
it does not assert that the
application never wakes over an entire session or detect polling slower than
the observation interval. RSS keeps the larger endpoint reading per interval,
then the best of those three intervals.

The original 250 MiB RSS limit is retained for a real GPU desktop, pending
manual gate 5. The initial Xvfb baseline is already about 272–290 MiB; software
rendering contributes resident memory and startup CPU, but its contribution has
not been separated from an application overrun. The additional 320 MiB ceiling
is deliberately an environment-specific regression limit, with roughly 10%
headroom above the observed range, not evidence that the 250 MiB desktop budget
passes. The software profile pins `LP_NUM_THREADS=4`, X11 and scale 1 to
reduce variation across headless machines. It also removes
`DBUS_SESSION_BUS_ADDRESS` and `AT_SPI_BUS_ADDRESS` (ADR 0065): started from a
desktop session the process would otherwise join that desktop's accessibility
bus through GTK's bridge and be woken by it, which is not the application
idling badly and is not what a hosted runner measures. CI and release preflight
run this profile; `--desktop` preserves the graphics, scale and session
environment and asserts 250 MiB. Both use the same harness and retain raw
process logs with `--output`.

If the ten-second startup watchdog fails, the launch record's
`startup_diagnostics` captures live state before SIGTERM/SIGKILL cleanup:
monotonic pre-spawn/deadline/capture timestamps, display/session environment,
process/thread states and wait channels, loaded mappings, and the X window tree
with map state and `_NET_WM_PID`. The failure-only worker
`tools/startup_diagnostics.py` uses the existing X11 runtime, not a GL probe.
Its X query is limited to two seconds, GDB's all-thread backtrace attempt to five,
and the collector as a whole to ten; retained command output and mappings are
capped at 128 KiB, threads/windows at 256, tree depth at 16, with truncation
reported. GDB disables debugger auto-load and debuginfod. Missing tools, denied
attachment, process exit, command errors and diagnostic timeouts are retained
without replacing the original startup failure or skipping cleanup. Cleanup's
signals, exit code and timing are also retained in the existing JSON artifact.
No collector runs on successful startup or the idle measurement path.

A missing PID-visible window does not by itself prove no frame was rendered:
a first-frame checkpoint can still be unmapped, and a viewable window can lack
PID metadata. These diagnostics are failure evidence, not a startup fix; local
synthetic capture checks cannot diagnose the old hosted timeout. A new failing
hosted first launch with this JSON is required before choosing a causal fix.

Do not change a threshold without its test and a stated reason. Each process
budget is checked with an injected production regression (first-frame sleep,
fast periodic wakeup, resident allocation), then the injection reverted.

## Running them

```sh
cargo test -p slugline_fountain --test parse_is_fast_enough
cargo test -p slugline_layout --test pagination_is_fast_enough   # --release for the table's figures
cargo test -p slugline_render_pdf --test export_is_fast_enough
./tools/test_linux_integration.sh                               # includes the keystroke benchmark
xvfb-run -a python3 tools/check_runtime_budgets.py --output target/runtime-budgets.json
```

The layout and export budgets relax in a debug build, so `cargo test` gates on a
gross regression rather than the number above; `--release` measures the table.
ADR 0022 records the repagination budgets and ADR 0005 the editor measurements.
