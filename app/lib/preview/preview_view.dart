// `PageView` is a scrolling widget in Flutter and a sheet of a pagination in
// the core. This file means the second one throughout, and the first one is not
// used here at all.
import 'dart:math' as math;

import 'package:flutter/material.dart' hide PageView;

import 'package:slugline/core/document_core.dart';
import 'package:slugline/editor/line_text_cache.dart';
import 'package:slugline/theme.dart';
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
///
/// ## Where it opens
///
/// At the sheet [opensAt] is printed on, found in the pagination this widget
/// was handed — the one it is about to draw — and not in a page number worked
/// out anywhere else. The editor's status line has a snapshot of its own, but
/// that one trails the text by a debounce and may not have arrived at all; the
/// sheet a place lands on is a fact about *this* pagination.
class PreviewView extends StatefulWidget {
  const PreviewView({
    required this.pagination,
    required this.paper,
    this.scale = 7.2,
    this.opensAt,
    super.key,
  });

  final PaginationView pagination;
  final PaperSize paper;

  /// Screen points per grid column. A column is a tenth of an inch (§5.2), so
  /// 7.2 is actual size at 72 dots to the inch.
  final double scale;

  /// The place in the script the preview is scrolled to when it first appears,
  /// or null for the top.
  ///
  /// Read once. A later pagination, paper or scale leaves the view where the
  /// reader has it, and so does a different value here.
  final PreviewAnchor? opensAt;

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

  /// Which of [sheetsOf] the text at [anchor] is printed on, or null when
  /// neither it nor anything before it reached a page.
  ///
  /// A lookup in the paginator's own answer, with nothing estimated: the sheet
  /// carrying that wrapped line of that block. Where the pagination has no such
  /// line — the block's line count has moved since, or the paginator printed
  /// nothing for it — the block's nearest line above stands in for it, and for
  /// a block with no lines at all, the sheet the text before it ends on. A
  /// note, a synopsis or a section heading prints nothing, and a caret in one
  /// is read as being where the page was left.
  ///
  /// Only lines carrying a [LayoutLineView.sourceLine] count. A `(MORE)` or a
  /// `CONT'D` names the block it was generated for and is none of its lines.
  static int? sheetOf(PaginationView pagination, PreviewAnchor anchor) {
    final sheets = sheetsOf(pagination);
    final lastSheetOf = <int, int>{};
    int? firstOfBlock;
    int? atOrAbove;
    var nearestLine = -1;
    for (var index = 0; index < sheets.length; index++) {
      for (final line in sheets[index].page.lines) {
        final block = line.block;
        final sourceLine = line.sourceLine;
        if (block == null || sourceLine == null) continue;
        lastSheetOf[block] = index;
        if (block != anchor.block) continue;
        firstOfBlock ??= index;
        if (sourceLine <= anchor.sourceLine && sourceLine >= nearestLine) {
          nearestLine = sourceLine;
          atOrAbove = index;
        }
      }
    }
    if (atOrAbove ?? firstOfBlock case final sheet?) return sheet;
    for (final block in anchor.earlierBlocks) {
      if (lastSheetOf[block] case final sheet?) return sheet;
    }
    return null;
  }

  @override
  State<PreviewView> createState() => _PreviewViewState();
}

/// A place in the script, named the way the paginator names one.
///
/// [LayoutLineView.block] and [LayoutLineView.sourceLine] are how a line of a
/// pagination says where it came from, so the same pair is how the editor says
/// where the caret is. The editor's wrapping and the paginator's are one
/// contract (`docs/LINE_BREAKING.md`), which is what makes a wrapped-line index
/// mean the same line on both sides.
class PreviewAnchor {
  const PreviewAnchor({
    required this.block,
    required this.sourceLine,
    this.earlierBlocks = const [],
  });

  /// The block's id — the `BlockId` the bridge speaks.
  final int block;

  /// Which wrapped line of [block], counting from zero.
  final int sourceLine;

  /// The ids of the blocks before [block], nearest first.
  ///
  /// Document order is the editor's to give: block ids are identities, not
  /// positions, and a pagination holds only the blocks that printed. This is
  /// what lets a place inside something that prints nothing be found at all.
  final List<int> earlierBlocks;
}

class _PreviewViewState extends State<PreviewView> {
  /// One cache for every sheet, not one per sheet: repeated lines (scene
  /// headings, transitions) share laid-out painters across pages, and the key
  /// is the content plus the resolved style, so a fresh pagination or a new
  /// scale misses by construction rather than painting stale.
  final LineTextCache _lineCache = LineTextCache();

  /// The desk showing around every sheet and between two of them.
  static const double _gap = 24;

  /// Made in the first layout rather than in `initState`: where the list opens
  /// depends on how tall the pane is, and a position has to be right before the
  /// first frame — one that is out of range is sprung back into it, in view.
  ScrollController? _scroll;

  @override
  void dispose() {
    _scroll?.dispose();
    _lineCache.dispose();
    super.dispose();
  }

  /// How far down the list opens, for a pane [viewport] tall.
  ///
  /// The top of the sheet [PreviewView.opensAt] is on, with the same margin
  /// above it that the first sheet has in a preview opened at the top — or as
  /// near to that as the end of the list allows.
  ///
  /// Page 1 opens at the top instead, title page and all. It is the start of
  /// the script, and the title page has no caret position of its own: the top
  /// of the script is the only place a writer can be said to be looking at it
  /// from, and scrolling past it there would hide it above the fold.
  ///
  /// The arithmetic is the list's own — [build] gives it this extent — so the
  /// offset is a count of sheets and nothing is measured.
  double _openingOffset(
    int sheetCount,
    PreviewGeometry geometry,
    double viewport,
  ) {
    final anchor = widget.opensAt;
    if (anchor == null) return 0;
    final sheet = PreviewView.sheetOf(widget.pagination, anchor);
    final firstPage = widget.pagination.titlePage == null ? 0 : 1;
    if (sheet == null || sheet <= firstPage) return 0;
    final extent = geometry.height + _gap;
    final length = _gap + sheetCount * extent;
    return math.min(sheet * extent, math.max(0.0, length - viewport));
  }

  @override
  Widget build(BuildContext context) {
    final sheets = PreviewView.sheetsOf(widget.pagination);
    final geometry = PreviewGeometry(paper: widget.paper, scale: widget.scale);
    return LayoutBuilder(
      builder: (context, constraints) => ListView.builder(
        key: const Key('preview-sheets'),
        controller: _scroll ??= ScrollController(
          initialScrollOffset: _openingOffset(
            sheets.length,
            geometry,
            constraints.maxHeight,
          ),
        ),
        // Every sheet is the same paper, and the list is told so rather than
        // left to find out. A list that has to measure its children lays out
        // every sheet above the one it opens on before it can draw that one,
        // and guesses at the length of the rest; told the extent, it goes
        // straight there and its scroll bar is exact. The gap under a sheet is
        // part of its item, so the last one keeps the margin the first has.
        padding: const EdgeInsets.fromLTRB(_gap, _gap, _gap, 0),
        itemExtent: geometry.height + _gap,
        itemCount: sheets.length,
        itemBuilder: (context, index) => Padding(
          padding: const EdgeInsets.only(bottom: _gap),
          child: _Sheet(
            sheet: sheets[index],
            geometry: geometry,
            lineCache: _lineCache,
          ),
        ),
      ),
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
  const _Sheet({
    required this.sheet,
    required this.geometry,
    required this.lineCache,
  });

  final PreviewSheet sheet;
  final PreviewGeometry geometry;
  final LineTextCache lineCache;

  @override
  Widget build(BuildContext context) {
    final colours = context.colours;
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
            // page, and a dark one would be a picture of something else — which
            // is why this is the one surface in the application that is not a
            // theme token but a `paper` one.
            color: colours.paper,
            border: Border.all(color: colours.paperEdge),
            // The one shadow left in the application, and the only place one is
            // honest: a sheet of paper lying on a desk really does cast one.
            boxShadow: const [
              BoxShadow(
                color: Color(0x40000000),
                blurRadius: 6,
                offset: Offset(0, 2),
              ),
            ],
          ),
          child: Stack(
            children: [
              Positioned.fill(
                child: CustomPaint(
                  painter: _PagePainter(
                    lines: page.lines,
                    geometry: geometry,
                    ink: colours.onPaper,
                    lineCache: lineCache,
                  ),
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
          child: Text(
            line.content,
            style: _textStyle(geometry, context.colours.onPaper),
          ),
        ),
      ),
    );
  }
}

class _PagePainter extends CustomPainter {
  _PagePainter({
    required this.lines,
    required this.geometry,
    required this.ink,
    required this.lineCache,
  });

  final List<LayoutLineView> lines;
  final PreviewGeometry geometry;

  /// Ink on paper. Passed in rather than read from a `ColorScheme`, because a
  /// painter has no [Theme] to ask.
  final Color ink;

  /// Owned by the [PreviewView] state and shared across sheets. A scroll frame
  /// repaints the same lines; re-laying them is the frame's whole cost.
  final LineTextCache lineCache;

  @override
  void paint(Canvas canvas, Size size) {
    final style = _textStyle(geometry, ink);
    for (final line in lines) {
      if (line.kind == LayoutLineKind.pageNumber) continue;
      var column = line.column;
      for (final run in line.runs) {
        final painter = lineCache.line(
          run.text,
          style.copyWith(
            fontWeight: run.bold ? FontWeight.bold : FontWeight.normal,
            fontStyle: run.italic ? FontStyle.italic : FontStyle.normal,
            decoration: run.underline
                ? TextDecoration.underline
                : TextDecoration.none,
          ),
        );
        final at = geometry.at(line.row, column);
        // Centred within the row's box, on the printed baseline grid.
        painter.paint(
          canvas,
          Offset(at.dx, at.dy + (geometry.row - painter.height) / 2),
        );
        column += run.text.runes.length;
      }
    }
  }

  @override
  bool shouldRepaint(_PagePainter old) =>
      old.lines != lines ||
      old.ink != ink ||
      old.geometry.scale != geometry.scale ||
      old.geometry.paper != geometry.paper;
}

/// The preview is a picture of the printed page, so it is set in the face that
/// prints it. Before the face was bundled this was the system's monospace and
/// the preview was only approximately the PDF; now the two agree.
TextStyle _textStyle(PreviewGeometry geometry, Color ink) => TextStyle(
  fontFamily: scriptFontFamily,
  fontSize: geometry.fontSize,
  height: 1.0,
  color: ink,
);
