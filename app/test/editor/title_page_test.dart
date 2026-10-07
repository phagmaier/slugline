import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:slugline/core/document_core.dart';
import 'package:slugline/editor/title_page_dialog.dart';

import '../support/fake_core.dart';

/// §Phase 7's title page: editable in the app, stored in the Fountain title page
/// block.
///
/// What this can prove is the half that is Dart's — that the boxes show what the
/// core holds and that typing in one reaches the core as a `Key: value` pair.
/// What a title page *is*, which keys mean the same thing, and what canonical
/// order means are Fountain questions answered in `crates/fountain` and proved
/// by `cargo test` (ADR 0011).
void main() {
  late FakeCore core;

  setUp(() {
    core = FakeCore.single(BlockKind.action, 'Something happens.');
  });

  Future<void> open(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: TitlePageDialog(core: core)),
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder box(String key) => find.byKey(Key('title-field-$key'));

  testWidgets('every field §Phase 7 names has a box', (tester) async {
    await open(tester);
    for (final key in [
      'Title',
      'Credit',
      'Author',
      'Source',
      'Draft date',
      'Contact',
      'Notes',
    ]) {
      expect(box(key), findsOneWidget, reason: '$key is a §Phase 7 field');
    }
  });

  testWidgets('the boxes show what the document holds', (tester) async {
    core.title.addAll(const [
      TitleEntryView(key: 'Title', value: 'Big Fish'),
      TitleEntryView(key: 'Author', value: 'Ed Bloom'),
    ]);
    await open(tester);

    expect(tester.widget<TextField>(box('Title')).controller!.text, 'Big Fish');
    expect(
      tester.widget<TextField>(box('Author')).controller!.text,
      'Ed Bloom',
    );
    expect(tester.widget<TextField>(box('Source')).controller!.text, '');
  });

  testWidgets('typing a field writes it through the core', (tester) async {
    await open(tester);
    await tester.enterText(box('Draft date'), '26 July 2026');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(core.titleEdits, contains(('Draft date', '26 July 2026')));
    expect(
      core.titlePage().map((entry) => (entry.key, entry.value)),
      contains(('Draft date', '26 July 2026')),
    );
  });

  testWidgets('editing a multi-line Contact preserves its line breaks', (
    tester,
  ) async {
    const contact =
        'Next Level Productions\n1588 Mission Dr.\nSolvang, CA 93463';
    core.title.add(const TitleEntryView(key: 'Contact', value: contact));
    await open(tester);

    await tester.enterText(box('Contact'), '${contact}0');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(core.titleEdits, contains(('Contact', '${contact}0')));
    expect(
      core.titlePage().map((entry) => (entry.key, entry.value)),
      contains(('Contact', '${contact}0')),
    );
  });

  testWidgets('clearing a field removes it from the file', (tester) async {
    core.title.add(const TitleEntryView(key: 'Contact', value: 'nobody@here'));
    await open(tester);
    await tester.enterText(box('Contact'), '');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(core.titlePage(), isEmpty);
  });

  testWidgets('a key the form does not name is shown and kept', (tester) async {
    // The format allows any key, and a writer who typed `Revision Colour:` into
    // their script has said something the application does not get to forget.
    core.title.add(const TitleEntryView(key: 'Revision Colour', value: 'Blue'));
    await open(tester);

    expect(find.text('Also in this file'), findsOneWidget);
    expect(box('Revision Colour'), findsOneWidget);
    expect(
      tester.widget<TextField>(box('Revision Colour')).controller!.text,
      'Blue',
    );

    await tester.enterText(box('Revision Colour'), 'Pink');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(core.titleEdits.last, ('Revision Colour', 'Pink'));
  });

  testWidgets('closing the dialog commits the box the caret is still in', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => TitlePageDialog.show(context, core),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // Typed, and then the window closed without leaving the box — the ordinary
    // way to finish typing in one, and it must not be the way to lose it.
    await tester.enterText(box('Title'), 'Untitled Two');
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();

    expect(
      core.titlePage().map((entry) => (entry.key, entry.value)),
      contains(('Title', 'Untitled Two')),
    );
  });
}
