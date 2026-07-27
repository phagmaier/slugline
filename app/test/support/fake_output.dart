import 'package:slugline/core/document_core.dart';

/// A [ScreenplayOutput] for widget tests.
///
/// It does **not** paginate. It hands back a [PaginationView] a test built by
/// hand, which is exactly the right input for the things Dart owns here: the
/// preview draws what the paginator says and the export dialog does what the
/// core answers. What a screenplay's pages actually are is decided in
/// `crates/layout` and proved by `cargo test` (ADR 0011).
class FakeOutput implements ScreenplayOutput {
  FakeOutput(this.pagination);

  PaginationView pagination;

  /// Every setup [paginate] was asked for, in order.
  final List<PageSetup> setups = [];

  /// Every PDF export, as `(path, setup, overwrite)`.
  final List<(String, PageSetup, bool)> pdfExports = [];

  /// Destinations the core would refuse, as it would refuse them.
  final Set<String> existingFiles = {};
  final Set<String> openScripts = {};

  /// Set to answer a pagination as stale, the way a document typed into while
  /// the worker ran comes back (ADR 0020).
  bool stale = false;

  /// Set to answer that the handle names nothing.
  bool closed = false;

  @override
  Future<PaginationOutcome> paginate(PageSetup setup) async {
    setups.add(setup);
    if (closed) return const PaginationOutcome.noSuchDocument();
    return stale
        ? PaginationOutcome.stale(pagination: pagination)
        : PaginationOutcome.current(pagination: pagination);
  }

  @override
  Future<SaveOutcome> exportPdf(
    String path, {
    required PageSetup setup,
    bool overwrite = false,
  }) async {
    if (openScripts.contains(path)) {
      return SaveOutcome.failed(
        failure: SaveFailure.scriptIsOpen,
        path: path,
        message: '$path is open here',
      );
    }
    if (!overwrite && existingFiles.contains(path)) {
      return SaveOutcome.failed(
        failure: SaveFailure.alreadyExists,
        path: path,
        message: '$path is already there',
      );
    }
    pdfExports.add((path, setup, overwrite));
    existingFiles.add(path);
    return SaveOutcome.saved(path: path, bytes: 4096, backup: null);
  }
}

/// A pagination shaped like a short script: a title page and two numbered
/// pages, with a speech the second page carries on from.
///
/// The values are the ones `crates/layout` produces for this shape — a page
/// number at row -3, content from row 0, a `(MORE)` and a `CHARACTER (CONT'D)`
/// around a split — written out here so a widget test can assert on what the
/// preview does with them without a native library.
PaginationView samplePagination({bool titlePage = true, int pages = 2}) {
  PageView page(int number) => PageView(
    number: number,
    lines: [
      LayoutLineView(
        row: -3,
        column: 60 - '$number.'.length,
        content: '$number.',
        sourceLine: null,
        kind: LayoutLineKind.pageNumber,
      ),
      LayoutLineView(
        row: 1,
        column: 0,
        content: 'INT. LIBRARY - DAY',
        block: number * 10,
        sourceLine: 0,
        kind: LayoutLineKind.content,
      ),
      LayoutLineView(
        row: 3,
        column: 22,
        content: number == 1 ? 'NADIA' : "NADIA (CONT'D)",
        block: number * 10 + 1,
        sourceLine: number == 1 ? 0 : null,
        kind: number == 1 ? LayoutLineKind.content : LayoutLineKind.continued,
      ),
      LayoutLineView(
        row: 4,
        column: 10,
        content: 'We agreed on the unopened post.',
        block: number * 10 + 2,
        sourceLine: 0,
        kind: LayoutLineKind.content,
      ),
      if (number == 1)
        LayoutLineView(
          row: 5,
          column: 22,
          content: '(MORE)',
          block: 12,
          sourceLine: null,
          kind: LayoutLineKind.more,
        ),
    ],
  );

  return PaginationView(
    revision: 7,
    generation: 7,
    pageCount: pages,
    titlePage: titlePage
        ? PageView(
            number: null,
            lines: [
              LayoutLineView(
                row: 18,
                column: 21,
                content: 'THE LONG WAY ROUND',
                sourceLine: null,
                kind: LayoutLineKind.title,
              ),
              LayoutLineView(
                row: 20,
                column: 25,
                content: 'Written by',
                sourceLine: null,
                kind: LayoutLineKind.title,
              ),
            ],
          )
        : null,
    pages: [for (var number = 1; number <= pages; number++) page(number)],
    stats: PaginationStats(
      blockHits: 0,
      blockMisses: 3,
      reusedPages: 0,
      reusedTailPages: 0,
      breakRuleIterations: 2,
      fellBackToNaive: false,
    ),
  );
}
