// `PageView` is a scrolling widget in Flutter and a sheet of a pagination in
// the core. This file means the second one throughout, and the first one is not
// used here at all.
import 'package:flutter/material.dart' hide PageView;

import 'package:slugline/core/document_core.dart';
import 'package:slugline/typography.dart';

/// The paginated preview (§Phase 7).
///
/// ## What this widget is, and what it is not
///
/// It is a **viewer for a [PaginationView]**. It draws characters at the row and
/// column the paginator put them at, and it makes no layout decision of its own:
/// no wrapping, no page filling, no widow control, no opinion about where a
/// scene heading may sit. §Phase 7's rule — "rendered from the *same*
/// `PaginatedScript` the PDF uses, never a second layout implementation" — is
/// enforced by there being nothing here that could be a second implementation.
/// Page boundaries, page numbers, real line wrapping, dialogue splits, explicit
/// breaks and the title page are all visible because the paginator produced all
/// six, not because this file knows about any of them.
///
/// ## Zoom
///
/// [PreviewGeometry.scale] is this view's own, and the editor's text size is not
/// an input to it — nor will Phase 10's preference be. It multiplies the size of
/// a grid cell on screen and nothing else: the rows, the columns and the page
/// count are what came back from Rust at every scale, which is what
/// `test/preview/preview_zoom_test.dart` holds it to.
class PreviewView extends StatelessWidget {
  const PreviewView({
    required this.pagination,
    required this.paper,
    this.scale = 7.2,
    super.key,
  });

  final PaginationView pagination;
  final PaperSize paper;

  /// Screen points per grid column. A column is a tenth of an inch (§5.2), so
  /// 7.2 is actual size at 72 dots to the inch.
  final double scale;

  /// Every sheet of a pagination, title page first.
  ///
  /// The order the PDF writes them in, and the reason the title page is not
  /// page one: it is not in [PaginationView.pages] at all.
  static List<PreviewSheet> sheetsOf(PaginationView pagination) => [
    if (pagination.titlePage case final title?)
      PreviewSheet(page: title, isTitlePage: true),
    for (final page in pagination.pages)
      PreviewSheet(page: page, isTitlePage: false),
  ];

  @override
  Widget build(BuildContext context) {
    final sheets = sheetsOf(pagination);
    final geometry = PreviewGeometry(paper: paper, scale: scale);
    return ListView.separated(
      key: const Key('preview-sheets'),
      padding: const EdgeInsets.all(24),
      itemCount: sheets.length,
      separatorBuilder: (_, _) => const SizedBox(height: 24),
      itemBuilder: (context, index) =>
          _Sheet(sheet: sheets[index], geometry: geometry),
    );
  }
}

/// One sheet of a pagination, and whether it is the unnumbered title page.
class PreviewSheet {
  const PreviewSheet({required this.page, required this.isTitlePage});

  final PageView page;
  final bool isTitlePage;
}

/// Where a grid cell is on screen.
///
/// The same arithmetic `render_pdf::Geometry` does, in screen points rather than
/// PostScript ones, and derived from §5.2's two constants rather than from
/// anything to do with the editor.
class PreviewGeometry {
  const PreviewGeometry({required this.paper, required this.scale});

  final PaperSize paper;
  final double scale;

  /// §5.2: ten characters to the inch.
  double get column => scale;

  /// §5.2: six lines to the inch, so a row is ten sixths of a column.
  double get row => scale * 10 / 6;

  /// §5.2: the text area starts 1.5 inches — fifteen columns — from the left,
  /// and one inch — six rows — below the top.
  double get left => 15 * column;
  double get top => 6 * row;

  /// The paper, in tenths of an inch: 8.5 × 11, or 210 × 297 mm. Measured in
  /// columns in both directions, because a column is the tenth of an inch the
  /// grid is built from and a row is ten sixths of one.
  double get width => switch (paper) {
    PaperSize.usLetter => 85 * column,
    PaperSize.a4 => 82.6772 * column,
  };

  double get height => switch (paper) {
    PaperSize.usLetter => 110 * column,
    PaperSize.a4 => 116.9291 * column,
  };

  /// Twelve point at ten characters to the inch (§5.1), scaled with the grid.
  double get fontSize => column * 12 / 7.2;

  /// The top-left corner of a grid cell. Rows and columns may be negative — the
  /// page number sits above the text area and a scene number beside it.
  Offset at(int gridRow, int gridColumn) =>
      Offset(left + gridColumn * column, top + gridRow * row);
}

class _Sheet extends StatelessWidget {
  const _Sheet({required this.sheet, required this.geometry});

  final PreviewSheet sheet;
  final PreviewGeometry geometry;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final page = sheet.page;
    return Center(
      child: Semantics(
        label: sheet.isTitlePage
            ? 'Title page'
            : 'Page ${page.number ?? '?'} of the screenplay',
        child: Container(
          key: Key(
            sheet.isTitlePage
                ? 'preview-title-page'
                : 'preview-page-${page.number}',
          ),
          width: geometry.width,
          height: geometry.height,
          decoration: BoxDecoration(
            // Paper is white in both themes. A preview is a picture of a printed
            // page, and a dark one would be a picture of something else.
            color: Colors.white,
            border: Border.all(color: dark ? Colors.white24 : Colors.black26),
            boxShadow: const [
              BoxShadow(
                color: Colors.black26,
                blurRadius: 6,
                offset: Offset(0, 2),
              ),
            ],
          ),
          child: Stack(
            children: [
              Positioned.fill(
                child: CustomPaint(
                  painter: _PagePainter(lines: page.lines, geometry: geometry),
                ),
              ),
              for (final line in page.lines)
                if (line.kind == LayoutLineKind.pageNumber)
                  _PageNumber(
                    key: Key('preview-page-number-${page.number}'),
                    line: line,
                    geometry: geometry,
                  ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PageNumber extends StatelessWidget {
  const _PageNumber({required this.line, required this.geometry, super.key});

  final LayoutLineView line;
  final PreviewGeometry geometry;

  @override
  Widget build(BuildContext context) {
    final at = geometry.at(line.row, line.column);
    return Positioned(
      left: at.dx,
      top: at.dy,
      height: geometry.row,
      child: ExcludeSemantics(
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text(line.content, style: _textStyle(geometry)),
        ),
      ),
    );
  }
}

class _PagePainter extends CustomPainter {
  _PagePainter({required this.lines, required this.geometry});

  final List<LayoutLineView> lines;
  final PreviewGeometry geometry;

  @override
  void paint(Canvas canvas, Size size) {
    final style = _textStyle(geometry);
    for (final line in lines) {
      if (line.content.isEmpty || line.kind == LayoutLineKind.pageNumber) {
        continue;
      }
      final painter = TextPainter(
        text: TextSpan(text: line.content, style: style),
        textDirection: TextDirection.ltr,
      )..layout();
      final at = geometry.at(line.row, line.column);
      // Centred within the row's box, so that a preview row sits on the
      // baseline grid the printed one does.
      painter.paint(
        canvas,
        Offset(at.dx, at.dy + (geometry.row - painter.height) / 2),
      );
    }
  }

  @override
  bool shouldRepaint(_PagePainter old) =>
      old.lines != lines ||
      old.geometry.scale != geometry.scale ||
      old.geometry.paper != geometry.paper;
}

/// The preview is a picture of the printed page, so it is set in the face that
/// prints it. Before the face was bundled this was the system's monospace and
/// the preview was only approximately the PDF; now the two agree.
TextStyle _textStyle(PreviewGeometry geometry) => TextStyle(
  fontFamily: scriptFontFamily,
  fontSize: geometry.fontSize,
  height: 1.0,
  color: Colors.black,
);
