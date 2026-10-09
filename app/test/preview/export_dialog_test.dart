import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:slugline/core/document_core.dart';
import 'package:slugline/preview/export_dialog.dart';

import '../support/fake_core.dart';
import '../support/fake_output.dart';

/// Copy exports leave the active session alone, require explicit replacement
/// approval, and refuse to overwrite an open script.
void main() {
  /// The export dialog is 940 by 700; the default test surface is 800 by 600.
  /// Giving the test a window the dialog fits in is the alternative to
  /// scrolling to every button before tapping it.
  setUp(() {
    final view = TestWidgetsFlutterBinding.ensureInitialized()
        .platformDispatcher
        .views
        .first;
    view.physicalSize = const Size(1280, 960);
    view.devicePixelRatio = 1.0;
    addTearDown(() {
      view.resetPhysicalSize();
      view.resetDevicePixelRatio();
    });
  });

  late FakeCore core;
  late FakeOutput output;
  String? answer;
  String? suggested;

  setUp(() {
    core = FakeCore.single(BlockKind.action, 'Something happens.')
      ..filePath = '/scripts/heat.fountain';
    // No title page in this fixture: it puts screenplay page one at the top
    // of the preview, where a test can see it without scrolling.
    output = FakeOutput(samplePagination(titlePage: false));
    answer = null;
    suggested = null;
  });

  Future<void> open(
    WidgetTester tester, {
    PageSetup initialSetup = const PageSetup(
      paper: PaperSize.usLetter,
      sceneNumbers: SceneNumbers.off,
      boldSceneHeadings: false,
      numberFirstPage: false,
      debugLinesPerPage: null,
    ),
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ExportDialog(
            core: core,
            output: output,
            initialSetup: initialSetup,
            chooseFile:
                (
                  context, {
                  required String title,
                  required String suggestedName,
                  required String? directory,
                }) async {
                  suggested = suggestedName;
                  return answer;
                },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  String report(WidgetTester tester) => tester
      .widget<SelectableText>(find.byKey(const Key('export-report')))
      .data!;

  testWidgets('saved page defaults drive the first preview', (tester) async {
    await open(
      tester,
      initialSetup: const PageSetup(
        paper: PaperSize.a4,
        sceneNumbers: SceneNumbers.right,
        boldSceneHeadings: true,
        numberFirstPage: true,
        debugLinesPerPage: null,
      ),
    );

    expect(output.setups.single.paper, PaperSize.a4);
    expect(output.setups.single.boldSceneHeadings, isTrue);
    expect(output.setups.single.numberFirstPage, isTrue);
    expect(output.setups.single.sceneNumbers, SceneNumbers.right);
    answer = '/scripts/bold-headings.pdf';
    await tester.tap(find.byKey(const Key('export-pdf')));
    await tester.pumpAndSettle();
    expect(output.pdfExports.single.$2.boldSceneHeadings, isTrue);
    expect(
      output.pdfExports.single.$2.numberFirstPage,
      isTrue,
      reason: 'changing paper in the dialog must not drop the saved option',
    );
  });

  testWidgets('exporting a PDF writes one and moves nothing', (tester) async {
    await open(tester);
    answer = '/scripts/heat.pdf';
    await tester.tap(find.byKey(const Key('export-pdf')));
    await tester.pumpAndSettle();

    expect(output.pdfExports.single.$1, '/scripts/heat.pdf');
    expect(output.pdfExports.single.$3, isFalse, reason: 'nothing to replace');
    expect(output.pdfExports.single.$2.boldSceneHeadings, isFalse);
    expect(output.pdfExports.single.$2.numberFirstPage, isFalse);
    expect(report(tester), contains('/scripts/heat.pdf'));

    // ADR 0029: the session did not move.
    expect(core.saves, isEmpty, reason: 'an export is not a save');
    expect(core.filePath, '/scripts/heat.fountain');
  });

  testWidgets(
    'a destination that is already there is asked about, then replaced',
    (tester) async {
      core.existingFiles.add('/scripts/copy.fountain');
      await open(tester);
      answer = '/scripts/copy.fountain';
      await tester.tap(find.byKey(const Key('export-fountain')));
      await tester.pumpAndSettle();

      expect(find.text('There is already a file there'), findsOneWidget);
      expect(core.exports, isEmpty, reason: 'nothing has been written yet');

      await tester.tap(find.text('Replace'));
      await tester.pumpAndSettle();
      expect(
        core.exports.single,
        ('/scripts/copy.fountain', true),
        reason: 'the second call is the answer to the question',
      );
    },
  );

  testWidgets('declining to replace writes nothing and says so', (
    tester,
  ) async {
    output.existingFiles.add('/scripts/heat.pdf');
    await open(tester);
    answer = '/scripts/heat.pdf';
    await tester.tap(find.byKey(const Key('export-pdf')));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(output.pdfExports, isEmpty);
    expect(report(tester), 'The file was left as it was.');
  });

  testWidgets('a script open here is refused, and the refusal is not retried', (
    tester,
  ) async {
    output.openScripts.add('/scripts/other.fountain');
    await open(tester);
    answer = '/scripts/other.fountain';
    await tester.tap(find.byKey(const Key('export-pdf')));
    await tester.pumpAndSettle();

    expect(output.pdfExports, isEmpty);
    expect(
      find.text('There is already a file there'),
      findsNothing,
      reason: 'this is a refusal, not a question',
    );
    expect(report(tester), contains('script open here'));
  });

  testWidgets('closing the chooser is not a failure', (tester) async {
    await open(tester);
    answer = null;
    await tester.tap(find.byKey(const Key('export-pdf')));
    await tester.pumpAndSettle();

    expect(output.pdfExports, isEmpty);
    expect(find.byKey(const Key('export-report')), findsNothing);
  });

  testWidgets('a stale pagination is still shown rather than a blank window', (
    tester,
  ) async {
    // ADR 0020: it is a correct pagination of the text that was there a moment
    // ago, and the export takes its own fresher one.
    output.stale = true;
    await open(tester);
    expect(find.byKey(const Key('preview-page-1')), findsOneWidget);
  });

  testWidgets('actual size is 100% and fit width fills the pane', (
    tester,
  ) async {
    await open(tester);
    await tester.ensureVisible(find.byKey(const Key('preview-actual-size')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('preview-actual-size')));
    await tester.pumpAndSettle();
    expect(
      tester.widget<Text>(find.byKey(const Key('preview-scale-percent'))).data,
      '100%',
    );

    await tester.ensureVisible(find.byKey(const Key('preview-fit-width')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('preview-fit-width')));
    await tester.pumpAndSettle();
    // The pane is narrower than an actual-size sheet, so fitting grows the
    // scale without leaving the slider's range — and the label tracks it.
    final slider = tester.widget<Slider>(
      find.byKey(const Key('preview-scale')),
    );
    expect(slider.value, greaterThan(4.2));
    expect(slider.value, lessThanOrEqualTo(slider.max));
    expect(
      tester.widget<Text>(find.byKey(const Key('preview-scale-percent'))).data,
      '${(slider.value / 7.2 * 100).round()}%',
    );
  });

  FdxExportOutcome needs(int revision, String warning) =>
      FdxExportOutcome.needsConfirmation(
        warnings: [warning],
        revision: revision,
      );

  FdxExportOutcome finished(
    SaveOutcome outcome, {
    List<String> warnings = const [],
  }) => FdxExportOutcome.finished(outcome: outcome, warnings: warnings);

  testWidgets(
    'FDX warning cancellation refuses all writes and keeps dirty session',
    (tester) async {
      core.apply(
        EditCommand.replaceText(
          block: 1,
          startUtf16: 0,
          endUtf16: 0,
          with_: 'New words. ',
        ),
      );
      final source = core.source();
      final journal = core.journalState;
      core.fdxOutcomes.add(
        needs(4, 'Outline metadata uses a conversion mapping.'),
      );
      await open(tester);
      answer = '/scripts/copy.fdx';
      await tester.tap(find.byKey(const Key('export-fdx')));
      await tester.pumpAndSettle();
      expect(suggested, 'heat.fdx');
      expect(core.fdxWrites, isEmpty);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(core.fdxWrites, isEmpty);
      expect(core.source(), source);
      expect(core.journalState, journal);
      expect(core.dirty, isTrue);
      expect(core.path, '/scripts/heat.fountain');
      expect(core.saves, isEmpty);
    },
  );

  testWidgets('changed FDX revision requires renewed approval before writing', (
    tester,
  ) async {
    core.fdxOutcomes.addAll([
      needs(4, 'First snapshot warning'),
      needs(5, 'Changed snapshot warning'),
      finished(
        const SaveOutcome.saved(
          path: '/scripts/copy.fdx',
          bytes: 20,
          backup: null,
        ),
      ),
    ]);
    await open(tester);
    answer = '/scripts/copy.fdx';
    await tester.tap(find.byKey(const Key('export-fdx')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Export copy'));
    await tester.pumpAndSettle();
    expect(find.text('Changed snapshot warning'), findsOneWidget);
    expect(core.fdxWrites, isEmpty);
    await tester.tap(find.text('Export copy'));
    await tester.pumpAndSettle();
    expect(core.fdxWrites, ['/scripts/copy.fdx']);
    expect(report(tester), contains('Wrote'));
  });

  testWidgets('paper controls remain usable after approving many FDX warnings', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 720);
    final warnings = [
      for (final kind in [
        'Section:1',
        'Section:2',
        'Section:3',
        'Section:4',
        'Section:5',
        'Section:6',
        'Synopsis',
        'Note',
      ])
        'Nonprinting $kind (including notes/omitted text) becomes visible '
            'Action text to the recipient; Slugline metadata retains original '
            'semantics only for Slugline re-import.',
    ];
    core.fdxOutcomes.addAll([
      FdxExportOutcome.needsConfirmation(warnings: warnings, revision: 4),
      finished(
        const SaveOutcome.saved(
          path: '/scripts/copy.fdx',
          bytes: 2000,
          backup: null,
        ),
        warnings: warnings,
      ),
    ]);
    await open(tester);
    answer = '/scripts/copy.fdx';
    await tester.tap(find.byKey(const Key('export-fdx')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Export copy'));
    await tester.pumpAndSettle();
    expect(find.text('A4').hitTestable(), findsOneWidget);
    await tester.tap(find.text('A4'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<RadioGroup<PaperSize>>(find.byType(RadioGroup<PaperSize>))
          .groupValue,
      PaperSize.a4,
    );
  });

  testWidgets('cancelling renewed FDX warning writes nothing', (tester) async {
    core.fdxOutcomes.addAll([
      needs(4, 'Earlier warning'),
      needs(5, 'Later warning'),
    ]);
    await open(tester);
    answer = '/scripts/copy.fdx';
    await tester.tap(find.byKey(const Key('export-fdx')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Export copy'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(core.fdxWrites, isEmpty);
  });

  testWidgets('FDX overwrite confirmation retains approved revision', (
    tester,
  ) async {
    core.fdxOutcomes.addAll([
      needs(7, 'Conversion warning'),
      finished(
        const SaveOutcome.failed(
          failure: SaveFailure.alreadyExists,
          path: '/scripts/copy.fdx',
          message: 'Already exists',
        ),
      ),
      finished(
        const SaveOutcome.saved(
          path: '/scripts/copy.fdx',
          bytes: 20,
          backup: null,
        ),
      ),
    ]);
    await open(tester);
    answer = '/scripts/copy.fdx';
    await tester.tap(find.byKey(const Key('export-fdx')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Export copy'));
    await tester.pumpAndSettle();
    expect(find.text('There is already a file there'), findsOneWidget);
    expect(core.fdxWrites, isEmpty);
    await tester.tap(find.text('Replace'));
    await tester.pumpAndSettle();
    expect(core.fdxWrites, ['/scripts/copy.fdx']);
    expect(core.saveAsCalls, isEmpty);
  });

  testWidgets('FDX overwrite cancellation leaves destination alone', (
    tester,
  ) async {
    core.fdxOutcomes.add(
      finished(
        const SaveOutcome.failed(
          failure: SaveFailure.alreadyExists,
          path: '/scripts/copy.fdx',
          message: 'Already exists',
        ),
      ),
    );
    await open(tester);
    answer = '/scripts/copy.fdx';
    await tester.tap(find.byKey(const Key('export-fdx')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(core.fdxWrites, isEmpty);
    expect(report(tester), 'The file was left as it was.');
  });

  for (final failure in [SaveFailure.scriptIsOpen, SaveFailure.noSpace]) {
    testWidgets('FDX $failure is shown after approval and never retried', (
      tester,
    ) async {
      core.fdxOutcomes.addAll([
        needs(7, 'Conversion warning'),
        finished(
          SaveOutcome.failed(
            failure: failure,
            path: '/scripts/copy.fdx',
            message: 'No disk space for this copy',
          ),
        ),
      ]);
      await open(tester);
      answer = '/scripts/copy.fdx';
      await tester.tap(find.byKey(const Key('export-fdx')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Export copy'));
      await tester.pumpAndSettle();
      expect(core.fdxWrites, isEmpty);
      expect(find.text('There is already a file there'), findsNothing);
      expect(
        report(tester),
        contains(
          failure == SaveFailure.scriptIsOpen
              ? 'script open here'
              : 'No disk space',
        ),
      );
      expect(report(tester), isNot(contains('Wrote')));
    });
  }

  testWidgets('closing the FDX chooser never reaches the write API', (
    tester,
  ) async {
    await open(tester);
    answer = null;
    await tester.tap(find.byKey(const Key('export-fdx')));
    await tester.pumpAndSettle();
    expect(core.fdxWrites, isEmpty);
    expect(find.byKey(const Key('export-report')), findsNothing);
  });

  testWidgets('unmounting FDX warning dialog cannot authorize a write', (
    tester,
  ) async {
    core.fdxOutcomes.add(needs(8, 'Conversion warning'));
    await open(tester);
    answer = '/scripts/copy.fdx';
    await tester.tap(find.byKey(const Key('export-fdx')));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    expect(core.fdxWrites, isEmpty);
  });
}
