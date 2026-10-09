import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:slugline/core/document_core.dart';
import 'package:slugline/editor/autosave.dart';
import 'package:slugline/editor/editor_controller.dart';
import 'package:slugline/editor/editor_page.dart';

import '../support/fake_core.dart';
import '../support/pending_file_choice.dart';

/// §Phase 4's autosave rules, tested where they live.
///
/// The clock is in Dart on purpose — see `lib/editor/autosave.dart` — so this is
/// where the rules can be checked: debounced after inactivity, on a hard
/// interval regardless, and never while a modal is open or a composition is
/// running. What a save *does* to a file is Rust's, and `cargo test` covers it
/// (ADR 0011).
void main() {
  /// A driver over a one-block script, with short timers so the test is quick.
  ({
    AutosaveDriver driver,
    FakeCore core,
    _Ticker changes,
    List<SaveOutcome> outcomes,
  })
  setUpDriver({
    Duration idle = const Duration(milliseconds: 20),
    Duration interval = const Duration(milliseconds: 100),
    bool enabled = true,
  }) {
    final core = FakeCore.single(BlockKind.action, 'John enters.')
      ..filePath = '/scripts/heat.fountain';
    final changes = _Ticker();
    final outcomes = <SaveOutcome>[];
    final driver = AutosaveDriver(
      core: core,
      changes: changes,
      idle: idle,
      interval: interval,
      enabled: enabled,
      onOutcome: outcomes.add,
    );
    addTearDown(driver.dispose);
    return (driver: driver, core: core, changes: changes, outcomes: outcomes);
  }

  /// One keystroke: an edit through the core, then the notification the
  /// controller would have sent.
  void type(FakeCore core, _Ticker changes, String text) {
    core.apply(
      EditCommand.replaceText(
        block: 1,
        startUtf16: 0,
        endUtf16: 0,
        with_: text,
      ),
    );
    changes.tick();
  }

  testWidgets('a pause after typing saves once', (tester) async {
    final it = setUpDriver();
    type(it.core, it.changes, 'a');
    expect(it.core.saves, isEmpty, reason: 'not immediately');

    await tester.pump(const Duration(milliseconds: 40));
    await tester.pumpAndSettle();
    expect(it.core.saves, [('/scripts/heat.fountain', true)]);
    expect(it.core.dirty, isFalse);
  });

  testWidgets('typing keeps pushing the idle save out', (tester) async {
    final it = setUpDriver();
    for (var keystroke = 0; keystroke < 5; keystroke++) {
      type(it.core, it.changes, 'a');
      await tester.pump(const Duration(milliseconds: 15));
    }
    expect(
      it.core.saves,
      isEmpty,
      reason: 'the writer has not stopped, so the debounce has not elapsed',
    );

    await tester.pump(const Duration(milliseconds: 40));
    await tester.pumpAndSettle();
    expect(it.core.saves.length, 1);
  });

  testWidgets('changed preferences re-arm or disable the live clock', (
    tester,
  ) async {
    final it = setUpDriver(idle: const Duration(seconds: 1));
    type(it.core, it.changes, 'a');
    it.driver.reconfigure(
      enabled: false,
      idle: const Duration(milliseconds: 10),
      interval: const Duration(milliseconds: 20),
    );
    await tester.pump(const Duration(milliseconds: 50));
    expect(it.core.saves, isEmpty, reason: 'turning autosave off cancels it');

    it.driver.reconfigure(
      enabled: true,
      idle: const Duration(milliseconds: 10),
      interval: const Duration(milliseconds: 20),
    );
    await tester.pump(const Duration(milliseconds: 30));
    await tester.pumpAndSettle();
    expect(it.core.saves.length, 1, reason: 'the dirty document was re-armed');
  });

  testWidgets('a writer who never pauses is still saved by the interval', (
    tester,
  ) async {
    // The reason the interval exists: a good session has no two-second pause in
    // it, and the debounce alone would never fire.
    final it = setUpDriver(
      idle: const Duration(milliseconds: 500),
      interval: const Duration(milliseconds: 60),
    );
    for (var keystroke = 0; keystroke < 10; keystroke++) {
      type(it.core, it.changes, 'a');
      await tester.pump(const Duration(milliseconds: 20));
    }
    await tester.pumpAndSettle();
    expect(it.core.saves, isNotEmpty, reason: 'the hard interval fired');
  });

  testWidgets('no autosave while a modal is open, and one the moment it closes', (
    tester,
  ) async {
    final it = setUpDriver();
    it.driver.suppress('modal');
    type(it.core, it.changes, 'a');
    await tester.pump(const Duration(milliseconds: 40));
    expect(it.core.saves, isEmpty);
    expect(it.driver.pending, isTrue, reason: 'owed, not cancelled');

    it.driver.release('modal');
    await tester.pumpAndSettle();
    expect(
      it.core.saves.length,
      1,
      reason:
          '§10 does not allow a save to be dropped because the timing was awkward',
    );
  });

  testWidgets('no autosave during a composition', (tester) async {
    final it = setUpDriver();
    it.driver.suppress('composing');
    type(it.core, it.changes, '日');
    await tester.pump(const Duration(milliseconds: 40));
    expect(it.core.saves, isEmpty);

    it.driver.release('composing');
    await tester.pumpAndSettle();
    expect(it.core.saves.length, 1);
  });

  testWidgets('two holds both have to be released', (tester) async {
    final it = setUpDriver();
    it.driver
      ..suppress('modal')
      ..suppress('composing');
    type(it.core, it.changes, 'a');
    await tester.pump(const Duration(milliseconds: 40));

    it.driver.release('modal');
    await tester.pump(const Duration(milliseconds: 20));
    expect(it.core.saves, isEmpty, reason: 'the composition is still running');

    it.driver.release('composing');
    await tester.pumpAndSettle();
    expect(it.core.saves.length, 1);
  });

  testWidgets('an external-change check holds every save until the decision', (
    tester,
  ) async {
    final it = setUpDriver();
    final choice = pendingFileChoice(tester);
    type(it.core, it.changes, 'Mine. ');
    it.core.onDisk = 'Somebody else wrote this.\n';
    final hold = Completer<void>();
    it.core.holdExternalChanges = hold;
    final controller = EditorController(it.core);
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: EditorPage(controller: controller, autosave: it.driver),
      ),
    );

    final page = tester.state<EditorPageState>(find.byType(EditorPage));
    final checking = page.handleExternalChange();
    final explicitSave = page.save();
    await tester.pump(const Duration(milliseconds: 40));
    expect(
      it.core.saves,
      isEmpty,
      reason: 'neither autosave nor Ctrl+S may pass the pending comparison',
    );
    expect(it.driver.suppressed, isTrue);

    hold.complete();
    await tester.pumpAndSettle();
    expect(find.text('Keep mine'), findsOneWidget);
    expect(it.core.saves, isEmpty, reason: 'the conflict is still unresolved');

    await tester.tap(find.text('Export a copy…'));
    await tester.pumpAndSettle();
    choice.complete(null);
    await tester.pumpAndSettle();
    expect(find.text('Keep mine'), findsOneWidget);
    expect(
      it.core.saves,
      isEmpty,
      reason: 'cancelling Save As must not release saves onto the old path',
    );

    await tester.tap(find.text('Keep mine'));
    await tester.pumpAndSettle();
    await checking;
    await explicitSave;
    expect(
      it.core.saves,
      isNotEmpty,
      reason: 'owed saves run after the choice',
    );
  });

  testWidgets('a clean document never starts a timer', (tester) async {
    // §1.3 budgets idle CPU at zero. A notification that changed nothing — a
    // caret move — must not leave anything ticking.
    final it = setUpDriver();
    it.changes.tick();
    expect(it.driver.pending, isFalse);
    await tester.pump(const Duration(milliseconds: 200));
    expect(it.core.saves, isEmpty);
  });

  testWidgets('overlapping modals keep autosave held until both finish', (
    tester,
  ) async {
    final it = setUpDriver();
    final controller = EditorController(it.core);
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: EditorPage(controller: controller, autosave: it.driver),
      ),
    );
    final page = tester.state<EditorPageState>(find.byType(EditorPage));
    final first = Completer<void>();
    final second = Completer<void>();
    final firstModal = page.withModal(() => first.future);
    final secondModal = page.withModal(() => second.future);
    type(it.core, it.changes, 'a');
    await tester.pump(const Duration(milliseconds: 40));

    first.complete();
    await tester.pump();
    await firstModal;
    expect(it.driver.suppressed, isTrue);
    expect(it.core.saves, isEmpty);

    second.complete();
    await tester.pump();
    await secondModal;
    expect(it.driver.suppressed, isFalse);
    expect(it.core.saves, hasLength(1));
  });

  testWidgets('a deferred save is forgotten when undo makes the script clean', (
    tester,
  ) async {
    final it = setUpDriver();
    it.driver.suppress('modal');
    type(it.core, it.changes, 'a');
    await tester.pump(const Duration(milliseconds: 40));
    expect(it.driver.pending, isTrue);

    it.core.markClean();
    it.changes.tick();
    expect(it.driver.pending, isFalse);
    it.driver.release('modal');
    await tester.pump();
    expect(it.core.saves, isEmpty);
  });

  testWidgets('releasing a modal after disposal cannot start an owed save', (
    tester,
  ) async {
    final it = setUpDriver();
    it.driver.suppress('modal');
    type(it.core, it.changes, 'a');
    await tester.pump(const Duration(milliseconds: 40));
    it.driver.dispose();
    it.driver.release('modal');
    await tester.pump();
    expect(it.core.saves, isEmpty);
    expect(it.driver.pending, isFalse);
  });

  testWidgets('an explicit save also stops the automatic interval when clean', (
    tester,
  ) async {
    final it = setUpDriver();
    type(it.core, it.changes, 'a');
    await it.core.save();
    it.core.saves.clear();

    // Explicit saves do not notify the editor controller. The next timer must
    // notice the clean document and retire both timers without another write.
    await tester.pump(const Duration(milliseconds: 40));
    await tester.pump(const Duration(milliseconds: 400));
    expect(it.core.saves, isEmpty);
    expect(it.driver.pending, isFalse);
  });

  testWidgets('an undo back to the saved state stops the pending save', (
    tester,
  ) async {
    final it = setUpDriver();
    type(it.core, it.changes, 'a');
    // Whatever the writer did, the core now says there is nothing to write.
    it.core.markClean();
    it.changes.tick();

    await tester.pump(const Duration(milliseconds: 60));
    await tester.pumpAndSettle();
    expect(it.core.saves, isEmpty);
    expect(it.driver.pending, isFalse);
  });

  testWidgets('a failed autosave is reported and the document stays dirty', (
    tester,
  ) async {
    final it = setUpDriver();
    it.core.refuseSaveWith = SaveFailure.noSpace;
    type(it.core, it.changes, 'a');
    await tester.pump(const Duration(milliseconds: 40));
    await tester.pump();
    // Not `pumpAndSettle`: the interval timer is still running, deliberately, so
    // there is nothing here that will ever settle.
    it.driver.dispose();

    expect(it.outcomes, isNotEmpty);
    expect(it.outcomes.first, isA<SaveOutcome_Failed>());
    expect(
      (it.outcomes.first as SaveOutcome_Failed).failure,
      SaveFailure.noSpace,
    );
    expect(it.core.dirty, isTrue, reason: 'nothing reached the file');
    // And it keeps trying: the document is still dirty, so the interval keeps
    // ticking. A disk that frees up gets written to without the writer doing
    // anything.
    expect(
      it.outcomes.every((outcome) => outcome is SaveOutcome_Failed),
      isTrue,
    );
  });

  testWidgets('turning autosave off means no timers at all', (tester) async {
    final it = setUpDriver(enabled: false);
    type(it.core, it.changes, 'a');
    await tester.pump(const Duration(milliseconds: 300));
    expect(it.core.saves, isEmpty);
    expect(it.driver.pending, isFalse);
  });

  testWidgets('saveNow writes immediately and cancels what was pending', (
    tester,
  ) async {
    final it = setUpDriver();
    type(it.core, it.changes, 'a');
    await it.driver.saveNow();
    expect(it.core.saves.length, 1);

    await tester.pump(const Duration(milliseconds: 200));
    expect(
      it.core.saves.length,
      1,
      reason: 'the pending timer did not fire too',
    );
  });

  // --- adopting a document that is already dirty -----------------------------
  //
  // Crash recovery hands the editor a document whose edits are ahead of its
  // file. No edit event will ever fire for those edits — they happened in a
  // process that is no longer running — so before this the clock did not start
  // until the writer typed. Reading what was recovered before touching the
  // keyboard is exactly what a person does at that moment (F2).

  testWidgets(
    'a document adopted dirty is saved without waiting for a keystroke',
    (tester) async {
      final it = setUpDriver();
      // Dirty on arrival, and nothing notified: this is what recovery looks like.
      type(it.core, it.changes, 'recovered');
      it.core.saves.clear();
      it.driver.dispose();

      final adopted = AutosaveDriver(
        core: it.core,
        changes: it.changes,
        idle: const Duration(milliseconds: 20),
        interval: const Duration(milliseconds: 100),
        onOutcome: (_) {},
      );
      addTearDown(adopted.dispose);
      expect(
        it.core.dirty,
        isTrue,
        reason: 'the recovered document arrives unsaved',
      );

      adopted.documentAdopted();
      expect(
        adopted.pending,
        isTrue,
        reason: 'the idle timer is armed at once',
      );

      await tester.pump(const Duration(milliseconds: 40));
      await tester.pumpAndSettle();
      expect(
        it.core.saves.length,
        1,
        reason: 'and it fires without an edit event',
      );
    },
  );

  testWidgets('adopting a clean document arms nothing', (tester) async {
    final it = setUpDriver();
    expect(it.core.dirty, isFalse);

    it.driver.documentAdopted();
    expect(it.driver.pending, isFalse);

    await tester.pump(const Duration(milliseconds: 300));
    expect(it.core.saves, isEmpty, reason: 'an ordinary open writes nothing');
  });

  testWidgets(
    'adopting dirty still leaves the interval running for a writer who never pauses',
    (tester) async {
      final it = setUpDriver(idle: const Duration(milliseconds: 200));
      type(it.core, it.changes, 'recovered');
      it.core.saves.clear();
      it.driver.dispose();

      final adopted = AutosaveDriver(
        core: it.core,
        changes: it.changes,
        idle: const Duration(milliseconds: 200),
        interval: const Duration(milliseconds: 50),
        onOutcome: (_) {},
      );
      addTearDown(adopted.dispose);
      adopted.documentAdopted();

      // The idle timer has not come due, so this is the interval's doing.
      await tester.pump(const Duration(milliseconds: 60));
      await tester.pumpAndSettle();
      expect(it.core.saves.length, 1);
    },
  );

  // --- a save that arrives while another is in flight (Phase 4A) -------------
  //
  // Ordering across two saves is the core's, not this class's: `cargo test`
  // covers the per-session lock in `crates/bridge/src/api/files.rs`. What is
  // Dart's, and what these check, is that the driver neither forgets the save
  // it declined nor stops its clock for text the file does not have.

  testWidgets(
    'an autosave that collides with one in flight is owed, not dropped',
    (tester) async {
      final it = setUpDriver();
      final held = Completer<void>();
      it.core.holdWrites = held;

      type(it.core, it.changes, 'a');
      await tester.pump(const Duration(milliseconds: 40));
      expect(it.core.saves.length, 1, reason: 'the first save is at the disk');

      type(it.core, it.changes, 'b');
      await tester.pump(const Duration(milliseconds: 40));
      expect(
        it.core.saves.length,
        1,
        reason: 'the second does not pile on top of the first',
      );

      held.complete();
      await tester.pumpAndSettle();
      expect(
        it.core.saves.length,
        2,
        reason: 'it happens once the first is done',
      );
      expect(
        it.core.onDisk,
        it.core.source(),
        reason: 'and it wrote the newest text',
      );
      expect(it.core.dirty, isFalse);
    },
  );

  testWidgets('an edit that lands mid-write does not stop the clock', (
    tester,
  ) async {
    final it = setUpDriver();
    final held = Completer<void>();
    it.core.holdWrites = held;

    type(it.core, it.changes, 'a');
    await tester.pump(const Duration(milliseconds: 40));
    expect(it.core.saves.length, 1);

    // Deliberately no `changes.tick()`: this is the edit the driver has
    // already been told about, arriving after the save planned its bytes.
    // Nothing is left to restart the timers, so if the finished save stops
    // them the text stays out of the file for good.
    it.core.apply(
      EditCommand.replaceText(block: 1, startUtf16: 0, endUtf16: 0, with_: 'b'),
    );
    held.complete();
    await tester.pump();
    expect(it.core.dirty, isTrue, reason: 'that edit is not in the file');

    it.core.saves.clear();
    await tester.pump(const Duration(milliseconds: 120));
    await tester.pumpAndSettle();
    expect(
      it.core.saves,
      isNotEmpty,
      reason: 'the interval is still running, so the edit is written after all',
    );
    expect(it.core.dirty, isFalse);
  });
}

/// Stands in for the `EditorController` as "something that says an edit
/// happened". The driver only needs a `Listenable`.
class _Ticker extends ChangeNotifier {
  void tick() => notifyListeners();
}
