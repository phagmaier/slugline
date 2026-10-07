// Phase 7's proofs, against the real `libslugline_bridge.so` and real files.
//
//     flutter test integration_test/export_test.dart -d linux
//
// `cargo test` covers the PDF itself — the subsetter, the golden hashes, the
// text extraction, the element indents — where it is, in Rust. The widget tests
// in `test/preview/` cover the preview and the export dialog, in Dart, against a
// pagination built by hand. What only this can prove is that the whole chain
// agrees: a title page typed in the editor reaches a PDF on disk that a viewer
// will open, through the bridge, and that an export leaves the writer's session
// exactly where it was.
//
// Everything here happens under a temporary XDG root, so the run cannot see or
// write the library index, journals or backups of the person running it.

import 'dart:io';

import 'package:flutter/material.dart' hide PageView;
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:slugline/core/core.dart';
import 'package:slugline/core/document_core.dart';
import 'package:slugline/src/rust/api/files.dart' as files;
import 'package:slugline/editor/editor_controller.dart';
import 'package:slugline/editor/editor_surface.dart';
import 'package:slugline/preview/export_dialog.dart';
import 'package:slugline/preview/preview_view.dart';
import 'package:slugline/settings/preferences_dialog.dart';

const _script = '''
Title: The Long Way Round
Credit: Written by
Author: Ada Lovelace

FADE IN:

INT. LIBRARY - DAWN

George watches the rain, *quietly*, and says nothing at all.

NADIA
(quietly)
We agreed on the unopened post.

CUT TO:
''';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late Directory root;
  late Directory scripts;

  setUpAll(() async {
    root = await Directory.systemTemp.createTemp('slugline-phase7-');
    scripts = await Directory('${root.path}/scripts').create(recursive: true);
    await Core.init(
      configDir: '${root.path}/config',
      dataDir: '${root.path}/data',
      stateDir: '${root.path}/state',
    );
  });

  tearDownAll(() async {
    await Core.instance.shutdown();
    if (root.existsSync()) await root.delete(recursive: true);
  });

  String path(String name) => '${scripts.path}/$name';

  /// Opens a script through the library, the way the application does.
  Future<(DocumentCore, ScreenplayOutput)> open(String name) async {
    final file = File(path(name));
    await file.writeAsString(_script);
    final handle = await files.libraryOpen(path: file.path);
    expect(handle, isNotNull, reason: 'the script opens');
    final core = RustDocumentCore.of(handle!);
    addTearDown(core.close);
    return (core, core);
  }

  const letter = PageSetup(
    paper: PaperSize.usLetter,
    sceneNumbers: SceneNumbers.off,
    boldSceneHeadings: false,
    numberFirstPage: false,
    debugLinesPerPage: null,
  );

  testWidgets('a script paginates and exports to a PDF a viewer will open', (
    tester,
  ) async {
    final (core, output) = await open('export.fountain');

    final outcome = await output.paginate(letter);
    final pagination = switch (outcome) {
      PaginationOutcome_Current(:final pagination) => pagination,
      PaginationOutcome_Stale(:final pagination) => pagination,
      PaginationOutcome_NoSuchDocument() => fail('the script is open'),
    };
    expect(pagination.pageCount, 1);
    expect(pagination.titlePage, isNotNull, reason: 'this script has one');
    expect(
      pagination.titlePage!.number,
      isNull,
      reason: 'and it is not page 1',
    );
    expect(pagination.pages.first.number, 1);

    final pdf = path('export.pdf');
    final wrote = await output.exportPdf(pdf, setup: letter);
    expect(wrote, isA<SaveOutcome_Saved>());

    final bytes = await File(pdf).readAsBytes();
    expect(String.fromCharCodes(bytes.take(8)), '%PDF-1.7');
    expect(bytes.length, (wrote as SaveOutcome_Saved).bytes);
    final text = String.fromCharCodes(bytes);
    expect(text, contains('/Type /Catalog'));
    expect(text, contains('/FontFile2'), reason: 'Courier Prime is embedded');
    expect(text.trimRight(), endsWith('%%EOF'));

    // The title page and screenplay page 1 are two sheets, in that order.
    // `/Type /Page /Parent` rather than `/Type /Page`, which the page *tree*
    // also matches.
    expect('/Type /Page /Parent'.allMatches(text).length, 2);

    // ADR 0029: an export copies and the session stays where it is.
    expect(core.path, path('export.fountain'));
    expect(core.dirty, isFalse);
    expect(await File(path('export.fountain')).readAsString(), _script);
  });

  testWidgets(
    'the title page is editable and reaches both the file and the PDF',
    (tester) async {
      final (core, output) = await open('titled.fountain');

      expect(
        core.titlePage().map((entry) => entry.key),
        containsAll(['Title', 'Credit', 'Author']),
      );
      core.setTitleField('Draft date', '26 July 2026');
      core.setTitleField('Contact', 'nobody@example.com');

      expect(core.source(), contains('Draft date: 26 July 2026'));
      expect(core.source(), contains('Contact: nobody@example.com'));
      expect(core.dirty, isTrue, reason: 'a title page edit is an edit');

      final saved = await core.save();
      expect(saved, isA<SaveOutcome_Saved>());
      expect(
        await File(path('titled.fountain')).readAsString(),
        contains('Draft date: 26 July 2026'),
      );

      final pdf = path('titled.pdf');
      expect(
        await output.exportPdf(pdf, setup: letter),
        isA<SaveOutcome_Saved>(),
      );
      final text = String.fromCharCodes(await File(pdf).readAsBytes());
      // The document title is the one the writer typed, as a UTF-16BE text
      // string — which is what a viewer shows in its window title.
      expect(text, contains('/Title <FEFF0054'));

      // Undo takes the field away again, through the same path.
      core.undo();
      expect(core.source(), isNot(contains('Contact:')));
    },
  );

  testWidgets('an export refuses a file that is there, and one that is open', (
    tester,
  ) async {
    final (core, output) = await open('refusals.fountain');
    final occupied = path('occupied.pdf');
    await File(occupied).writeAsString('not really a pdf');

    final refused = await output.exportPdf(occupied, setup: letter);
    expect((refused as SaveOutcome_Failed).failure, SaveFailure.alreadyExists);
    expect(await File(occupied).readAsString(), 'not really a pdf');

    final replaced = await output.exportPdf(
      occupied,
      setup: letter,
      overwrite: true,
    );
    expect(replaced, isA<SaveOutcome_Saved>());
    expect(
      String.fromCharCodes(await File(occupied).readAsBytes()),
      startsWith('%PDF'),
    );

    // The script's own file is never a destination, however firmly asked.
    final onto = await output.exportPdf(
      core.path!,
      setup: letter,
      overwrite: true,
    );
    expect((onto as SaveOutcome_Failed).failure, SaveFailure.scriptIsOpen);
    expect(await File(core.path!).readAsString(), _script);
  });

  testWidgets('the same script exports to the same bytes', (tester) async {
    // §Phase 7's determinism requirement, over the real bridge.
    //
    // The clock is masked out rather than pinned: `SOURCE_DATE_EPOCH` is a
    // process-wide environment variable and Dart cannot set one for the library
    // it has already loaded. Two exports a moment apart may land either side of
    // a second, and the `/ID` is a digest that includes the timestamp, so both
    // move together. Everything else — every page, every glyph, every offset in
    // the cross-reference table — must be identical, and
    // `crates/render_pdf/tests/golden.rs` pins the timestamp too.
    final (_, output) = await open('deterministic.fountain');
    final written = <String>[];
    for (var run = 0; run < 2; run++) {
      final pdf = path('run-$run.pdf');
      expect(
        await output.exportPdf(pdf, setup: letter),
        isA<SaveOutcome_Saved>(),
      );
      written.add(
        String.fromCharCodes(await File(pdf).readAsBytes())
            .replaceAll(RegExp(r'D:\d{14}'), 'D:00000000000000')
            .replaceAll(RegExp(r'/ID \[<[0-9A-F]+> <[0-9A-F]+>\]'), '/ID []'),
      );
    }
    expect(written[0].length, written[1].length);
    expect(written[0], written[1]);
  });

  testWidgets('A4 is a different pagination and a different page', (
    tester,
  ) async {
    final (_, output) = await open('a4.fountain');
    const a4 = PageSetup(
      paper: PaperSize.a4,
      sceneNumbers: SceneNumbers.off,
      boldSceneHeadings: false,
      numberFirstPage: false,
      debugLinesPerPage: null,
    );

    final pdf = path('a4.pdf');
    expect(await output.exportPdf(pdf, setup: a4), isA<SaveOutcome_Saved>());
    final text = String.fromCharCodes(await File(pdf).readAsBytes());
    expect(text, contains('/MediaBox [0 0 595.2756 841.8898]'));
  });

  testWidgets('native preview and PDF export follow the heading preference', (
    tester,
  ) async {
    final source = File(path('presentation.fountain'));
    const text = 'INT. LIBRARY - DAY\n\nHe reads *quietly*.\n';
    await source.writeAsString(text);
    final handle = await files.libraryOpen(path: source.path);
    final core = RustDocumentCore.of(handle!);
    addTearDown(core.close);
    final controller = EditorController(core);
    addTearDown(controller.dispose);

    for (final bold in [false, true]) {
      PreferencesView? chosen;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              return Scaffold(
                body: FilledButton(
                  onPressed: () async {
                    chosen = await PreferencesDialog.show(
                      context,
                      preferences: Core.instance.preferences(),
                      spelling: Core.instance.spellStatus(),
                    );
                  },
                  child: const Text('Preferences'),
                ),
              );
            },
          ),
        ),
      );
      await tester.tap(find.text('Preferences'));
      await tester.pumpAndSettle();
      final toggle = find.widgetWithText(SwitchListTile, 'Bold scene headings');
      await tester.scrollUntilVisible(
        toggle,
        250,
        scrollable: find.byType(Scrollable).last,
      );
      if (tester.widget<SwitchListTile>(toggle).value != bold) {
        await tester.tap(toggle);
        await tester.pumpAndSettle();
      }
      await tester.tap(find.byKey(const ValueKey('save preferences')));
      await tester.pumpAndSettle();
      expect(chosen!.boldSceneHeadings, bold);
      expect(await Core.instance.setPreferences(chosen!), isTrue);
      expect(Core.instance.preferences().boldSceneHeadings, bold);
      final setup = PageSetup(
        paper: PaperSize.usLetter,
        sceneNumbers: SceneNumbers.off,
        boldSceneHeadings: bold,
        numberFirstPage: false,
      );
      final pdf = path('presentation-$bold.pdf');
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Stack(
              children: [
                EditorSurface(controller: controller, boldSceneHeadings: bold),
                ExportDialog(
                  core: core,
                  output: core,
                  initialSetup: setup,
                  chooseFile:
                      (
                        context, {
                        required title,
                        required suggestedName,
                        required directory,
                      }) async => pdf,
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final preview = tester.widget<PreviewView>(find.byType(PreviewView));
      final lines = preview.pagination.pages.first.lines;
      final heading = lines.singleWhere(
        (line) => line.content == 'INT. LIBRARY - DAY',
      );
      expect(heading.runs.every((run) => run.bold == bold), isTrue);
      final action = lines.singleWhere(
        (line) => line.content == 'He reads *quietly*.',
      );
      expect(action.runs.map((run) => run.text).join(), 'He reads quietly.');
      expect(
        action.runs.singleWhere((run) => run.text == 'quietly').italic,
        isTrue,
      );
      await tester.tap(find.byKey(const Key('export-pdf')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('export-report')), findsOneWidget);
      final extracted = await Process.run('pdftohtml', [
        '-xml',
        '-stdout',
        '-i',
        pdf,
      ]);
      expect(extracted.exitCode, 0);
      final xml = extracted.stdout as String;
      expect(xml, contains('<i>quietly</i>'));
      expect(
        xml,
        bold
            ? contains('<b>INT. LIBRARY - DAY</b>')
            : contains('>INT. LIBRARY - DAY</text>'),
      );
      expect(core.source(), text);
      expect(core.dirty, isFalse);
    }
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('native preview and PDF export follow first-page numbering', (
    tester,
  ) async {
    // Long enough for a second page, and with no digit of its own: any `1.` or
    // `2.` that comes back out of the PDF is a page number.
    final source = File(path('numbering.fountain'));
    const line = 'George crosses the room again.';
    final text = '${List.filled(40, line).join('\n\n')}\n';
    await source.writeAsString(text);
    final handle = await files.libraryOpen(path: source.path);
    final core = RustDocumentCore.of(handle!);
    addTearDown(core.close);

    for (final numbered in [false, true, false]) {
      PreferencesView? chosen;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              return Scaffold(
                body: FilledButton(
                  onPressed: () async {
                    chosen = await PreferencesDialog.show(
                      context,
                      preferences: Core.instance.preferences(),
                      spelling: Core.instance.spellStatus(),
                    );
                  },
                  child: const Text('Preferences'),
                ),
              );
            },
          ),
        ),
      );
      await tester.tap(find.text('Preferences'));
      await tester.pumpAndSettle();
      final toggle = find.widgetWithText(
        SwitchListTile,
        'Number the first page',
      );
      await tester.scrollUntilVisible(
        toggle,
        250,
        scrollable: find.byType(Scrollable).last,
      );
      if (tester.widget<SwitchListTile>(toggle).value != numbered) {
        await tester.tap(toggle);
        await tester.pumpAndSettle();
      }
      await tester.tap(find.byKey(const ValueKey('save preferences')));
      await tester.pumpAndSettle();
      expect(chosen!.numberFirstPage, numbered);
      expect(await Core.instance.setPreferences(chosen!), isTrue);
      expect(Core.instance.preferences().numberFirstPage, numbered);

      final setup = PageSetup(
        paper: PaperSize.usLetter,
        sceneNumbers: SceneNumbers.off,
        boldSceneHeadings: false,
        numberFirstPage: numbered,
      );
      final pagination = switch (await core.paginate(setup)) {
        PaginationOutcome_Current(:final pagination) => pagination,
        PaginationOutcome_Stale(:final pagination) => pagination,
        PaginationOutcome_NoSuchDocument() => fail('the script is open'),
      };
      List<String> printed(PageView page) => [
        for (final line in page.lines)
          if (line.kind == LayoutLineKind.pageNumber) line.content,
      ];
      expect(pagination.pageCount, 2);
      expect(pagination.pages[0].number, 1, reason: 'counted either way');
      expect(printed(pagination.pages[0]), numbered ? ['1.'] : isEmpty);
      expect(printed(pagination.pages[1]), ['2.']);

      final pdf = path('numbering-$numbered.pdf');
      final existing = File(pdf);
      if (existing.existsSync()) existing.deleteSync();
      expect(await core.exportPdf(pdf, setup: setup), isA<SaveOutcome_Saved>());
      Future<String> sheet(int number) async {
        final extracted = await Process.run('pdftotext', [
          '-f',
          '$number',
          '-l',
          '$number',
          pdf,
          '-',
        ]);
        expect(extracted.exitCode, 0);
        return extracted.stdout as String;
      }

      final first = await sheet(1);
      expect(first, contains(line));
      expect(first.contains('1.'), numbered);
      expect(await sheet(2), contains('2.'));
      expect(core.source(), text);
      expect(core.dirty, isFalse);
    }
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
