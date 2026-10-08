# Fast native input investigation — B12

The CI correction and W10 were published first, independently of this change.
The starting tree was clean on `main` at `9b21f33`, exactly three commits ahead
of the live `origin/main` at `61466bb`. A normal fast-forward push published
`316f210`, `38a60b7` and `9b21f33`; no history was rewritten. The new hosted run is
[37764798245](https://github.com/phagmaier/slugline/actions/runs/37764798245),
for the full head `9b21f336118ea31505dc4511aac80e8e8d589434`. It completed
successfully in all five jobs, including the corrected writing workflow,
all later native suites and the hosted process budgets. Raw step conclusions
and logs are retained in `target/fast-input/hosted-ci.json` and
`target/fast-input/hosted-ci.log`. This hosted result applies to the published
CI/W10 head; it does not cover the separate B12 correction. The original
[failed run](https://github.com/phagmaier/slugline/actions/runs/37749124762)
shows `new.fountain` expected and `beta.fountain` observed. It does not record
chooser delivery; the controlled local hold, described in the CI commit,
established that separately.

## What failed and where

W10's original screenshot and exact saved observation remain in
`target/w10-smoke/installed-saved.png` and
`target/w10-smoke/fast-input-observation.fountain`. They show
`Installed command ready. Verifed hrough insalled assoiation.`. Its paced control
proved installation/edit/save/reopen, without establishing fast input correctness.

Fresh native-Wayland runs use isolated XDG roots and a disposable source:

```text
INT. INSTALLATION CHECK - DAY

Installed command ready.
```

The unchanged burst is ` Verified through installed association.`. The driver
holds only startup/caret positioning and post-burst observation outside that
burst; it does not pace its characters. Autosave is disabled in disposable
preferences so that journal records can be inspected before an explicit save.
No owner document, preferences or installation is changed.

The installed release reproduced incomplete text in
`target/fast-input/installed-ready/`: `Verified through intaled assciaion.`.
Its journal already held incomplete text before Ctrl+S. Immediate and later
saves match that text, excluding a save snapshot taken ahead of pending input.
The screenshot `ready-at-end.png` confirms the adopted document and end caret.
An earlier run, `installed-original/`, began before asynchronous editor adoption
and is retained as a harness failure, not valid burst evidence. Teardown failures
in the two installed runs are also retained; neither is claimed as a clean exit.

A temporary diagnostic release logs the surface's raw key events, incoming
`TextEditingValue`s, and outgoing `setEditingState` calls in
`target/fast-input/diagnostic-red/process.log`. All 40 supplied printable
key-down characters arrive in order. The 40 incoming platform updates later
lose letters: for example, `…through i` is followed by `…through n`. The
application echoes the earlier whole-block value after accepting each update.
At replacements it also sends pre-edit text while selecting the replacement
range. The asynchronous platform input model accepts those stale values and
subsequent typing proceeds from overwritten text. Its final incoming value,
the committed journal and both saves agree on the incomplete
`Verified through nstalled asocation.`. None of these updates has an active
composing range, so this is ordinary platform input synchronization rather than
an unfinished composition.

The behavior follows Flutter's
[asynchronous input synchronization contract](https://api.flutter.dev/flutter/services/TextInput-class.html):
platform plugins accept application editing states as sent. The pinned Flutter
3.44.8 `EditableTextState` implementation likewise batches edits and compares
the final value with its last known remote value before sending an update.
Context7 documentation and the local pinned SDK were consulted. Source reads
supplemented the codebase graph's abbreviated Dart method ranges.

## Correction and evidence

`EditorSurface` now remembers the last known remote editing value, suppresses
intermediate synchronization during a platform update, and sends only a final
value that differs. Accepted typing and composition require no echo. A changed
application caret, a newline that becomes a new block, and a refused core edit
still update the platform with their final state. Reattaching resets the remote
value so a new connection receives its initial state. No timer, keystroke delay,
shortcut retry, assertion relaxation or storage ordering change is introduced.

`target/fast-input/widget-red.log` retains both initial failing regressions.
Four passing widget cases also cover composition replacement, a structural
newline and a core refusal. The native persistence regression submits all
platform updates without pumping between them and verifies the core source,
journal count, an immediate save, Undo/Redo and exact reopen. Its delivered
values exercise the application contract; the separate desktop trace exercises
actual native key/channel delivery.

The corrected diagnostic release receives all 40 keys and 40 complete cumulative
platform values with zero outgoing state echoes during or after the burst.
Its before-save journal and immediate/later saved bytes are complete; it exits
cleanly with status 0. Evidence is in `target/fast-input/diagnostic-green/`.
The diagnostic burst took about 186 ms against about 188 ms before the fix.
Temporary prints and diagnostic imports were removed from production source
before the full checks.

The final uninstrumented release repeats the same unpaced burst with exact
before-save journal patches, immediate and later saves, visible reopened text,
and clean original/reopened exits (both status 0). A separate run sends the
burst and Ctrl+S in the same `wtype` invocation with no pause between typing and
Save; that first saved snapshot and its later save/reopen are also byte-exact.
Screenshots were inspected. These runs are retained in
`target/fast-input/release-before-save/` and
`target/fast-input/release-immediate-save/`. The latter exercises real native
shortcut ordering; it is distinct from the direct-client persistence regression.

Verification on the final correction:

- 649 Rust tests; Rust formatting/clippy and layering/version/docs checks.
- Enforced Dart lockfile, formatter check (110 files, none changed), clean
  Flutter analysis and all 675 widget tests.
- All seven native suites: 72 tests total, including IME and the added storage
  regression. Journalled keystroke p99: 4.37 ms.
- Serial final Linux release build and release network-isolation check.
- Native-Wayland unpaced input, same-burst Save, exact bytes and actual reopen,
  with no temporary diagnostic logging in the final release.

Raw outputs remain under `target/fast-input/`, including `rust-tests.log`,
`widgets.log`, `native-final.log`, `release-build.log` and `no-network.log`.
`analyze.log` and `native-first.log` retain initial regression-harness mistakes:
awaiting a synchronous close and comparing the `source` method rather than its
result. Those were corrected in the test, and the final analysis/native run
passes; they are not application-failure evidence. No dependency, lockfile,
Rust API, generated binding, golden, accepted ADR decision or budget changed.

## Boundaries

The verified B12 implementation is committed locally as `0cb58de`; it has not
been pushed, and no hosted success is claimed for it. The published CI/W10
boundary remains `origin/main` at `9b21f33`. No missing automated prerequisite
blocked this investigation or correction.

The owner-installed W10 executable remains the original build; verification of
the correction uses source-tree bundles. Local runtime idle-budget failure,
real-GPU memory gate, real ibus/CJK and other manual gates remain unresolved.
Hosted process-budget evidence is distinct from those local/manual claims.
X1, F7/X6 and unrelated side findings are untouched.

## Installed B12 follow-up — 2026-10-08

The earlier publication-boundary paragraphs above remain historical. B12 and
its completion record were pushed through `08c7a55`; hosted run
[37771088908](https://github.com/phagmaier/slugline/actions/runs/37771088908)
completed successfully in all five jobs. Raw results are retained in
`target/fast-input/b12-hosted-ci.json`.

Built with `./tools/package.sh`, passed `./tools/smoke_test_tarball.sh`, and ran
the generated user-local installer. Installed runner, Dart AOT library and Rust
library hashes match the staged package (`b12-installed-hashes.json`). The
actual installed executable passed unpaced input, exact before-save journal,
Save and visible reopen, with both process exits zero
(`installed-b12-before-save/`).

Two same-burst Ctrl+S runs saved the complete burst except its final period;
the settled journal and later saves/reopens contained the period. A third run
using identical unpaced injection passed, including a file observation after
settling and before the later Save. These are retained separately under
`installed-b12-immediate-save/`, `installed-b12-immediate-save-repeat/` and
`installed-b12-immediate-observed/`. A successful control does not close this
intermittent native Save-ordering finding. B12's stale-state overwrite fix
preserves the eventual text; the first native Save needs further investigation.

## Native Save ordering correction — B15

The incomplete first saves above are a separate, established snapshot-ordering
defect: the final native text update can reach Dart after the Ctrl+S handler.
Explicit Save now crosses a one-shot native queue acknowledgment before taking
the Rust snapshot. GTK forwards queued input before its idle response; Dart
then verifies the original editor is still mounted. Input is neither delayed
nor reconstructed, and Save writes one snapshot. Flutter's documented Linux
raw-key redispatch behavior and GLib's idle priority/ownership contract were
consulted; source reads supplemented partial native graph coverage.

Two widget regressions failed before the change. Both pass with a delayed
acknowledgment, including disposal while waiting. The native persistence test
requires the runner method itself, then verifies an explicit Save and actual
reopen. Three uninstrumented native-Wayland bursts pass with exact first-file
observations, settled pre-later-save bytes, later Save and actual reopen
(`save-order-barrier-1/` through `save-order-barrier-3/`); all original/reopened
process exits are zero. The passing temporary diagnostic run
`save-order-diagnostic-1/` is a control, not failure evidence; all trace prints
were removed before the corrected release and full checks.

Final local checks: 649 Rust tests, 690 widgets and 82 native tests; journalled
keystroke p99 6.53 ms. Enforced lockfile, formatting/clippy/analysis and repository
checks, serial release package, isolated tarball installation and network
isolation pass. Current Xvfb startup/idle/RSS pass; the earlier retained local
idle failure and GPU/IME manual gates remain open. B15's source publication and
final installed-package evidence follow below.

## Final publication and installed verification — 2026-10-08

B13 (`f34aed7`), B14 (`e15126d`) and B15 (`40cfad5`) were published through
`804ba18`. Hosted run
[37775929481](https://github.com/phagmaier/slugline/actions/runs/37775929481)
passes all five jobs, including the native suites, release process budgets,
MSRV, fuzz and package checks. Complete metadata and logs are retained in
`target/stabilization/hosted-ci.json` and `hosted-ci.log`.

The final source package reuses the serial verified release build and was
installed with its generated installer. All 18 installed bundle files match
the stage byte-for-byte (`final-installed-all-bundle-hashes.json`); the runner,
Dart and Rust hashes and shell launcher are recorded separately in
`final-installed-hashes.json`. `/proc/<pid>/exe` confirms initial launch and
actual reopen through `~/.local/bin/slugline` execute
`~/.local/lib/slugline/slugline`.

The unchanged unpaced text burst passes one before-save journal check and
three same-invocation Ctrl+S checks on that installed executable
(`target/fast-input/installed-final-before-save/` and
`installed-final-immediate-1/` through `installed-final-immediate-3/`). The
first saved file, settled file before the later Save, later saved file and
actual reopened file all match the expected bytes, including the final
period. All initial and reopened processes exit zero. The before-save journal
contains the exact outcome of each delivered character. Injection is unchanged;
its approximately 189–193 ms duration adds no character pacing.

Installed Note-only scripts edit, immediately Save and visibly reopen with
"No printed pages" in both continuous and page views, exact bytes and zero
exits (`installed-final-note-continuous/`, `installed-final-note-pageview/`).
The unit/native regressions separately cover empty scripts, other nonprinting
content and zero/nonzero transitions, with Rust's empty Action remaining one
blank printed sheet.

Two installed Xvfb Find smokes use actual OS clicks on Match case, Whole word
and the element menu, then Enter/Shift+Enter and Escape. Match navigation and
bar closing pass; unchanged CRLF script bytes are checked after every operation
and Save. Screenshots are retained in
`target/stabilization/pointer-smoke-installed/` and
`pointer-smoke-installed-repeat/`. Both processes subsequently SIGSEGV during
ordinary `WM_DELETE_WINDOW` shutdown: these are functional passes with failed
process exits, not clean native runs.

The preceding B12 CI package from run `37771088908` reproduces that shutdown
SIGSEGV twice without opening Find (`shutdown-b12-1/`, `shutdown-b12-2/`). The
same Flutter engine hash is used in both packages; the crashing raster-thread
stacks share the same Mesa `libgallium` offsets above Flutter frames. Metadata,
original and control cores, package hashes and the prior artifact remain under
`target/stabilization/`. This demonstrates a pre-fix shutdown failure but does
not establish its cause or close it. The earlier successful source-bundle close
and green hosted CI remain controls; the separate direct-XDestroyWindow
BadDrawable failure also remains retained. No shutdown workaround, dependency
change or budget relaxation was made.

The requested stabilization boundary is complete. The shutdown finding,
retained earlier idle-budget failure and real-GPU/manual IME gates remain open.
