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

The owner-installed W10 executable remains the original build; verification of
the correction uses source-tree bundles. Local runtime idle-budget failure,
real-GPU memory gate, real ibus/CJK and other manual gates remain unresolved.
Hosted process-budget evidence is distinct from those local/manual claims.
X1, F7/X6 and unrelated side findings are untouched.
