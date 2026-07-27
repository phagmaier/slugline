import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:slugline/core/document_core.dart';
import 'package:slugline/preview/export_dialog.dart';

import '../support/fake_core.dart';
import '../support/fake_output.dart';

/// §Phase 7's export commands.
///
/// Three requirements, and one test each:
///
/// * the export command calls `exportFountain`, and **only** Save As calls
///   `saveAs` — an export must never rebind the writer's session (ADR 0029);
/// * `AlreadyExists` is asked about and then re-exported with `overwrite: true`;
/// * `ScriptIsOpen` is reported as the refusal it is, and not retried.
void main() {
  /// The export dialog is 940 by 700; the default test surface is 800 by 600.
  /// Giving the test a window the dialog fits in is the alternative to
  /// scrolling to every button before tapping it.
  setUp(() {
    final view = TestWidgetsFlutterBinding.ensureInitialized().platformDispatcher.views.first;
    view.physicalSize = const Size(1280, 960);
    view.devicePixelRatio = 1.0;
    addTearDown(() {
      view.resetPhysicalSize();
      view.resetDevicePixelRatio();
    });
  });

  late FakeCore core;
  late FakeOutput output;
  late List<String> asked;
  String? answer;

  setUp(() {
    core = FakeCore.single(BlockKind.action, 'Something happens.')
      ..filePath = '/scripts/heat.fountain';
    // No title page in this fixture: it puts screenplay page one at the top
    // of the preview, where a test can see it without scrolling.
    output = FakeOutput(samplePagination(titlePage: false));
    asked = [];
    answer = null;
  });

  Future<void> open(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ExportDialog(
            core: core,
            output: output,
            chooseFile:
                (
                  context, {
                  required String title,
                  required String suggestedName,
                  required String? directory,
                }) async {
                  asked.add('$title|$suggestedName|$directory');
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

  testWidgets('exporting a PDF writes one and moves nothing', (tester) async {
    await open(tester);
    answer = '/scripts/heat.pdf';
    await tester.tap(find.byKey(const Key('export-pdf')));
    await tester.pumpAndSettle();

    expect(output.pdfExports.single.$1, '/scripts/heat.pdf');
    expect(output.pdfExports.single.$3, isFalse, reason: 'nothing to replace');
    expect(
      asked.single,
      'Export PDF|heat.pdf|/scripts',
      reason: 'the chooser starts beside the script and suggests its name',
    );
    expect(report(tester), contains('/scripts/heat.pdf'));

    // ADR 0029: the session did not move.
    expect(core.saves, isEmpty, reason: 'an export is not a save');
    expect(core.filePath, '/scripts/heat.fountain');
  });

  testWidgets('exporting a Fountain copy calls exportFountain, never saveAs', (
    tester,
  ) async {
    await open(tester);
    answer = '/elsewhere/copy.fountain';
    await tester.tap(find.byKey(const Key('export-fountain')));
    await tester.pumpAndSettle();

    expect(core.exports.single, ('/elsewhere/copy.fountain', false));
    expect(
      core.filePath,
      '/scripts/heat.fountain',
      reason: 'only Save As rebinds the session (ADR 0029)',
    );
    expect(core.saves, isEmpty);
    expect(core.dirty, isFalse, reason: 'and the dirty flag is untouched');
  });

  testWidgets('a destination that is already there is asked about, then replaced', (
    tester,
  ) async {
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
  });

  testWidgets('declining to replace writes nothing and says so', (tester) async {
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
}
