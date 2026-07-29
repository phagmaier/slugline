//! PDF output.
//!
//! Layering rule (§2.5): this crate depends on `layout` for the paginated script
//! and on `fountain` for what an asterisk means, and on nothing else. It
//! consumes a [`PaginatedScript`] and writes bytes.
//!
//! ## The renderer makes no layout decisions
//!
//! §Phase 7 states it as a requirement and it is worth being blunt about what it
//! rules out: there is no wrapping here, no page filling, no widow control, no
//! decision about where a scene heading may sit. Every row and column in the
//! output was decided by `crates/layout` and is copied. The arithmetic in
//! [`Geometry`] is the whole of the renderer's own opinion, and all it does is
//! multiply a grid cell by its size in points.
//!
//! The one thing this crate *does* interpret is inline emphasis, because ADR
//! 0019 put it here on purpose: `*italic*` is shown literally in the editor and
//! counted as columns by the paginator, and the PDF is the only place the
//! markers become a typeface instead of characters. Within a row the printed
//! text is drawn from the row's own left edge with no gap where a marker was
//! (ADR 0032); the consequence is that an emphasised transition or centred line
//! ends a marker or two short of where an unemphasised one would, because the
//! paginator aligned it while the markers still counted.
//!
//! ## Determinism
//!
//! Same script, same page setup, same [`DocumentInfo`] — same bytes, on every
//! machine. Nothing here reads a clock (the timestamp is an argument), nothing
//! iterates a `HashMap`, and the `/ID` is a digest of the content rather than
//! the random number the format expects. [`creation_time`] is the single
//! impurity, is not called by [`render`], and honours `SOURCE_DATE_EPOCH`.

mod fonts;
mod pdf;
mod sfnt;
pub mod sha256;

use std::collections::{BTreeMap, BTreeSet};
use std::panic::{catch_unwind, AssertUnwindSafe};

use slugline_fountain::emphasis;
use slugline_layout::{LayoutLineKind, Page, PageConfig, PaginatedScript};

use fonts::Style;
use pdf::{name, number, text_string, Pdf, Ref};
use sfnt::Face;

pub use fonts::OPEN_FONT_LICENCE;

/// Point size of the screenplay body font (§5.1).
pub const BODY_FONT_POINTS: f64 = 12.0;

/// PostScript points in an inch.
const POINTS_PER_INCH: f64 = 72.0;

/// Glyph space is a thousandth of an em, whatever the font's own units are.
const GLYPH_SPACE: f64 = 1000.0;

/// The advance every glyph is declared to have, in glyph space.
///
/// §5.2 fixes the grid at ten characters per inch, which at twelve point is
/// exactly six tenths of an em. Courier Prime's own advance is 1228/2048 —
/// 599.6 thousandths — so declaring the real number would drift a sixtieth of a
/// point per character and put the right-hand end of a sixty-column line a third
/// of a point off the grid. A PDF viewer positions text by the widths in the
/// font dictionary, so this is the number that decides where characters land,
/// and it is the number §5.2 asks for.
const DECLARED_ADVANCE: f64 = 600.0;

/// What the file says about itself.
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct DocumentInfo {
    pub title: String,
    pub author: String,
    /// Unix seconds. An argument rather than a clock reading, so that
    /// [`render`] is a pure function; [`creation_time`] is what a caller that
    /// wants "now, unless the build says otherwise" should use.
    pub created_epoch_seconds: i64,
}

/// `SOURCE_DATE_EPOCH` if it is set to a number, and the wall clock otherwise.
///
/// §Phase 7 requires the timestamp to be overridable, which is the reproducible
/// builds convention and the reason an exported PDF can be byte-compared in CI.
/// This is the only function in the crate that reads anything outside its
/// arguments, and [`render`] does not call it.
pub fn creation_time() -> i64 {
    if let Some(epoch) = std::env::var_os("SOURCE_DATE_EPOCH") {
        if let Some(seconds) = epoch
            .to_str()
            .and_then(|text| text.trim().parse::<i64>().ok())
        {
            return seconds;
        }
    }
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|since| since.as_secs() as i64)
        .unwrap_or(0)
}

/// Where a grid cell is, in points, on the paper the script was paginated for.
#[derive(Debug, Clone, Copy)]
struct Geometry {
    width: f64,
    height: f64,
    /// Points a column is wide, and a row is tall.
    column: f64,
    row: f64,
    /// The text area's left edge and the top it counts rows down from.
    left: f64,
    top: f64,
    /// How far below the top of a row its baseline sits.
    baseline: f64,
}

impl Geometry {
    fn of(config: &PageConfig) -> Geometry {
        use slugline_layout::metrics;

        let micrometres = |value: u32| f64::from(value) * POINTS_PER_INCH / 25_400.0;
        Geometry {
            width: micrometres(config.page_size.width_um()),
            height: micrometres(config.page_size.height_um()),
            column: POINTS_PER_INCH / f64::from(metrics::CHARACTERS_PER_INCH),
            row: POINTS_PER_INCH / f64::from(metrics::LINES_PER_INCH),
            // Column zero of the grid, which §5.2 puts 1.5 inches — fifteen
            // columns — from the paper's left edge.
            left: f64::from(metrics::TEXT_LEFT_COLUMN_FROM_PAGE) * POINTS_PER_INCH
                / f64::from(metrics::CHARACTERS_PER_INCH),
            top: micrometres(metrics::TOP_MARGIN_UM),
            // Courier Prime's ascender, so that a row's ascent and descent
            // together are exactly the row's height and consecutive baselines
            // are exactly a sixth of an inch apart.
            baseline: 1600.0 / 2048.0 * BODY_FONT_POINTS,
        }
    }

    fn x(&self, column: i32) -> f64 {
        self.left + f64::from(column) * self.column
    }

    fn baseline_y(&self, row: i32) -> f64 {
        self.height - self.top - f64::from(row) * self.row - self.baseline
    }
}

/// One stretch of text, placed and styled, ready to be turned into glyphs.
#[derive(Debug, Clone)]
struct Placed {
    row: i32,
    column: i32,
    style: Style,
    underline: bool,
    text: String,
}

/// Renders a paginated script.
///
/// `config` must be the one the script was paginated with: it is where the paper
/// size comes from, and a mismatch would place a 58-row A4 script on US Letter.
pub fn render(script: &PaginatedScript, config: &PageConfig, info: &DocumentInfo) -> Vec<u8> {
    render_inner(script, config, info, None)
}

/// Renders with one user-selected TrueType face for every emphasis style.
///
/// The fixed grid is still authoritative, so a proportional face cannot move
/// layout but will look wrong; the settings UI warns about that. Font files are
/// untrusted input, unlike the vendored Courier Prime family, so malformed data
/// is a reported failure rather than a process panic.
pub fn render_with_font(
    script: &PaginatedScript,
    config: &PageConfig,
    info: &DocumentInfo,
    font: &[u8],
) -> Result<Vec<u8>, String> {
    catch_unwind(AssertUnwindSafe(|| {
        render_inner(script, config, info, Some(font))
    }))
    .map_err(|_| "the selected PDF font is not a supported TrueType face".to_owned())
}

fn render_inner(
    script: &PaginatedScript,
    config: &PageConfig,
    info: &DocumentInfo,
    custom_font: Option<&[u8]>,
) -> Vec<u8> {
    let geometry = Geometry::of(config);
    let sheets = place(script);

    // Every character each face has to draw, so that the subsets are decided
    // before a single glyph id is written.
    let mut used: BTreeMap<Style, BTreeSet<char>> = BTreeMap::new();
    for placed in sheets.iter().flatten() {
        used.entry(placed.style)
            .or_default()
            .extend(placed.text.chars());
    }

    let mut document = Pdf::new();
    let pages_object = document.reserve();
    let embedded: BTreeMap<Style, Embedded> = used
        .iter()
        .map(|(style, characters)| {
            (
                *style,
                embed(&mut document, *style, characters, custom_font),
            )
        })
        .collect();

    let resources = {
        let entries: Vec<String> = embedded
            .iter()
            .map(|(style, font)| format!("{} {}", name(style.resource()), font.font))
            .collect();
        document.add(format!("<< /Font << {} >> >>", entries.join(" ")))
    };

    let media = format!(
        "[0 0 {} {}]",
        number(geometry.width),
        number(geometry.height)
    );
    let mut page_objects = Vec::with_capacity(sheets.len());
    for sheet in &sheets {
        let stream = content(sheet, &geometry, &embedded, custom_font);
        let contents = document.add_stream("", &stream);
        page_objects.push(document.add(format!(
            "<< /Type /Page /Parent {pages_object} /MediaBox {media} \
             /Resources {resources} /Contents {contents} >>"
        )));
    }

    let kids: Vec<String> = page_objects.iter().map(Ref::to_string).collect();
    document.put(
        pages_object,
        format!(
            "<< /Type /Pages /Kids [{}] /Count {} >>",
            kids.join(" "),
            page_objects.len()
        ),
    );
    let catalog = document.add(format!("<< /Type /Catalog /Pages {pages_object} >>"));

    let date = pdf::date_string(info.created_epoch_seconds);
    let info_object = document.add(format!(
        "<< /Title {} /Author {} /Creator {} /Producer {} \
         /CreationDate ({date}) /ModDate ({date}) >>",
        text_string(&info.title),
        text_string(&info.author),
        text_string("Slugline"),
        text_string("Slugline"),
    ));

    document.finish(
        catalog,
        info_object,
        &identifier(script, info, config, custom_font),
    )
}

// ---------------------------------------------------------------------------
// Placement — copying the paginator's grid, and reading emphasis off it
// ---------------------------------------------------------------------------

/// Turns the paginated script into placed, styled text, one `Vec` per sheet.
///
/// The title page is first and is not among `script.pages`, so it is neither
/// numbered nor counted — §Phase 7's requirement, which the paginator already
/// arranged and this only has to not undo.
fn place(script: &PaginatedScript) -> Vec<Vec<Placed>> {
    let sheets: Vec<&Page> = script
        .title_page
        .iter()
        .chain(script.pages.iter())
        .collect();
    let scanned = scan_paragraphs(&sheets);

    let mut placed: Vec<Vec<Placed>> = Vec::with_capacity(sheets.len().max(1));
    for (sheet, page) in sheets.iter().enumerate() {
        let mut out = Vec::new();
        for (index, line) in page.lines.iter().enumerate() {
            if line.content.is_empty() {
                continue;
            }
            match &scanned[sheet][index] {
                // The paginator decided the row and the column it starts at;
                // the runs follow one another from there. The cells the markers
                // occupied while it was measuring are closed up rather than
                // left blank (ADR 0032).
                Some(runs) => {
                    let mut column = i32::from(line.column);
                    for run in runs {
                        let width = run.text.chars().count() as i32;
                        out.push(Placed {
                            row: i32::from(line.row),
                            column,
                            style: Style::of(run.emphasis.bold, run.emphasis.italic),
                            underline: run.emphasis.underline,
                            text: run.text.clone(),
                        });
                        column += width;
                    }
                }
                // Furniture the paginator wrote itself. A stray asterisk in a
                // page number is a page number.
                None => out.push(Placed {
                    row: i32::from(line.row),
                    column: i32::from(line.column),
                    style: Style::Regular,
                    underline: false,
                    text: line.content.clone(),
                }),
            }
        }
        placed.push(out);
    }
    if placed.is_empty() {
        // A PDF with no pages is not a PDF. Nothing can produce this today —
        // paginating an empty document yields one empty page — but a file that
        // will not open is a worse answer than a blank sheet.
        placed.push(Vec::new());
    }
    placed
}

/// Reads emphasis off every line that has any, a paragraph at a time.
///
/// `None` for a line the renderer must not interpret. Everything else gets the
/// runs [`emphasis::scan`] found, and the reason this is a pass of its own is
/// the word *paragraph*: whether a marker means anything depends on whether it
/// has a partner, and its partner is very often on another row — sometimes on
/// another page, when a speech was split. A block's rows are gathered across
/// sheets and scanned together.
fn scan_paragraphs(sheets: &[&Page]) -> Vec<Vec<Option<Vec<emphasis::EmphasisRun>>>> {
    let mut scanned: Vec<Vec<Option<Vec<emphasis::EmphasisRun>>>> = sheets
        .iter()
        .map(|page| vec![None; page.lines.len()])
        .collect();

    // A paragraph is a block's rows, in order, with none missing. A `(MORE)` or
    // a page break between two of them does not end it; a different block, or a
    // row index that does not follow, does.
    let mut paragraph: Vec<(usize, usize)> = Vec::new();
    let mut open: Option<(u64, u16)> = None;
    let close = |paragraph: &mut Vec<(usize, usize)>,
                 scanned: &mut Vec<Vec<Option<Vec<emphasis::EmphasisRun>>>>| {
        if paragraph.is_empty() {
            return;
        }
        let rows: Vec<&str> = paragraph
            .iter()
            .map(|(sheet, line)| sheets[*sheet].lines[*line].content.as_str())
            .collect();
        for ((sheet, line), runs) in paragraph.drain(..).zip(emphasis::scan(&rows)) {
            scanned[sheet][line] = Some(runs);
        }
    };

    for (sheet, page) in sheets.iter().enumerate() {
        for (index, line) in page.lines.iter().enumerate() {
            if line.content.is_empty() {
                continue;
            }
            match line.kind {
                LayoutLineKind::Content => {
                    let source_line = line.source_line.unwrap_or(0);
                    let here = line.block.map(|block| (block.0, source_line));
                    let continues = matches!((open, here), (Some(was), Some(now)) if was.0 == now.0 && was.1 + 1 == now.1);
                    if !continues {
                        close(&mut paragraph, &mut scanned);
                    }
                    open = here;
                    paragraph.push((sheet, index));
                }
                // Generated from a block's text but not one of its rows, so it
                // is read on its own and does not interrupt the paragraph the
                // rows around it belong to.
                LayoutLineKind::More | LayoutLineKind::Continued | LayoutLineKind::Title => {
                    scanned[sheet][index] = Some(emphasis::scan_row(&line.content));
                }
                LayoutLineKind::Blank
                | LayoutLineKind::PageNumber
                | LayoutLineKind::SceneNumberLeft
                | LayoutLineKind::SceneNumberRight => {}
            }
        }
    }
    close(&mut paragraph, &mut scanned);
    scanned
}

// ---------------------------------------------------------------------------
// Fonts — one subset per face, embedded once for the whole document
// ---------------------------------------------------------------------------

/// An embedded face: the object a page names it by, and the glyphs it has.
struct Embedded {
    font: Ref,
    glyphs: BTreeMap<char, u16>,
}

fn embed(
    document: &mut Pdf,
    style: Style,
    characters: &BTreeSet<char>,
    custom_font: Option<&[u8]>,
) -> Embedded {
    let vendored = style.face();
    let bytes = custom_font.unwrap_or(vendored.bytes);
    let face = Face::parse(bytes);

    let wanted: BTreeSet<u16> = characters.iter().map(|c| face.glyph_for(*c)).collect();
    let kept = face.closure(&wanted);
    let (subset, mapping) = face.subset(&kept);
    let glyphs: BTreeMap<char, u16> = characters
        .iter()
        .map(|character| {
            let glyph = face.glyph_for(*character);
            (*character, mapping.get(&glyph).copied().unwrap_or(0))
        })
        .collect();

    let scale = GLYPH_SPACE / f64::from(face.units_per_em);
    let unit = |value: i16| number(f64::from(value) * scale);
    let postscript_name = if custom_font.is_some() {
        format!("SluglineSystemMonospace-{}", style.resource())
    } else {
        vendored.postscript_name.to_owned()
    };
    let base = format!("{}+{postscript_name}", subset_tag(&subset));

    let file = document.add_stream(&format!("/Length1 {}", subset.len()), &subset);
    let descriptor = document.add(format!(
        "<< /Type /FontDescriptor /FontName {} /Flags {} \
         /FontBBox [{} {} {} {}] /ItalicAngle {} /Ascent {} /Descent {} \
         /CapHeight {} /StemV {} /FontFile2 {file} >>",
        name(&base),
        // Fixed pitch, and non-symbolic because the glyphs are the standard
        // Latin ones reached through a standard encoding.
        1 | 32 | if face.italic_angle != 0.0 { 64 } else { 0 },
        unit(face.bbox[0]),
        unit(face.bbox[1]),
        unit(face.bbox[2]),
        unit(face.bbox[3]),
        number(face.italic_angle),
        unit(face.ascender),
        unit(face.descender),
        unit(face.cap_height),
        // The conventional estimate from the weight class; nothing renders from
        // it, and no viewer needs to synthesise this face because it is here.
        if face.weight_class >= 700 { 120 } else { 80 },
    ));
    let descendant = document.add(format!(
        "<< /Type /Font /Subtype /CIDFontType2 /BaseFont {} \
         /CIDSystemInfo << /Registry (Adobe) /Ordering (Identity) /Supplement 0 >> \
         /FontDescriptor {descriptor} /DW {} /CIDToGIDMap /Identity >>",
        name(&base),
        number(DECLARED_ADVANCE),
    ));
    let to_unicode = document.add_stream("", to_unicode_cmap(&glyphs).as_bytes());
    let font = document.add(format!(
        "<< /Type /Font /Subtype /Type0 /BaseFont {} /Encoding /Identity-H \
         /DescendantFonts [{descendant}] /ToUnicode {to_unicode} >>",
        name(&base),
    ));

    Embedded { font, glyphs }
}

/// The six-letter subset prefix a `/BaseFont` name carries.
///
/// Required to be unique per subset so that two PDFs merged into one do not
/// collide; derived from the subset's own bytes so that it is also the same
/// every time the same subset is written.
fn subset_tag(subset: &[u8]) -> String {
    sha256::digest(subset)[..6]
        .iter()
        .map(|byte| char::from(b'A' + byte % 26))
        .collect()
}

/// The `/ToUnicode` CMap: what each glyph in this subset says when it is copied
/// out of the page. §Phase 7 wants selectable, searchable text, and without this
/// a viewer has glyph numbers and nothing else.
fn to_unicode_cmap(glyphs: &BTreeMap<char, u16>) -> String {
    use std::fmt::Write as _;

    // Inverted, so that two characters sharing a glyph resolve to one — the
    // lower codepoint, because a `BTreeMap` insert order says so.
    let mut mapping: BTreeMap<u16, char> = BTreeMap::new();
    for (character, glyph) in glyphs {
        mapping.entry(*glyph).or_insert(*character);
    }
    mapping.remove(&0);

    let mut cmap = String::from(
        "/CIDInit /ProcSet findresource begin\n\
         12 dict begin\n\
         begincmap\n\
         /CIDSystemInfo << /Registry (Adobe) /Ordering (UCS) /Supplement 0 >> def\n\
         /CMapName /Adobe-Identity-UCS def\n\
         /CMapType 2 def\n\
         1 begincodespacerange\n<0000> <FFFF>\nendcodespacerange\n",
    );
    // The format caps a block at a hundred entries.
    for chunk in mapping.iter().collect::<Vec<_>>().chunks(100) {
        let _ = writeln!(cmap, "{} beginbfchar", chunk.len());
        for (glyph, character) in chunk {
            let mut units = [0u16; 2];
            let encoded = character.encode_utf16(&mut units);
            let _ = write!(cmap, "<{glyph:04X}> <");
            for unit in encoded {
                let _ = write!(cmap, "{unit:04X}");
            }
            let _ = writeln!(cmap, ">");
        }
        cmap.push_str("endbfchar\n");
    }
    cmap.push_str("endcmap\nCMapName currentdict /CMap defineresource pop\nend\nend\n");
    cmap
}

// ---------------------------------------------------------------------------
// Content streams
// ---------------------------------------------------------------------------

fn content(
    sheet: &[Placed],
    geometry: &Geometry,
    embedded: &BTreeMap<Style, Embedded>,
    custom_font: Option<&[u8]>,
) -> Vec<u8> {
    use std::fmt::Write as _;

    // Parse the custom font face once for underline metrics, rather than
    // re-parsing it for every underlined run. Vendored faces are parsed
    // per-style on first use and cached — the four Courier Prime variants may
    // have small metric differences.
    let custom_underline = custom_font.map(|bytes| {
        let face = Face::parse(bytes);
        let scale = BODY_FONT_POINTS / f64::from(face.units_per_em);
        (
            f64::from(face.underline_position) * scale,
            f64::from(face.underline_thickness) * scale,
        )
    });
    let mut vendored_underline: BTreeMap<Style, (f64, f64)> = BTreeMap::new();

    let mut text = String::from("BT\n");
    let mut rules = String::new();
    let mut current: Option<Style> = None;
    for placed in sheet {
        let Some(font) = embedded.get(&placed.style) else {
            continue;
        };
        if current != Some(placed.style) {
            let _ = writeln!(
                text,
                "{} {} Tf",
                name(placed.style.resource()),
                number(BODY_FONT_POINTS)
            );
            if custom_font.is_some() {
                // One selected face has no family metadata telling us where
                // sibling bold/italic files live. Preserve screenplay emphasis
                // without guessing paths: PDF's fill-and-stroke mode supplies
                // a modest bold, and a text-matrix shear supplies italic.
                if matches!(placed.style, Style::Bold | Style::BoldItalic) {
                    text.push_str("2 Tr\n0.35 w\n");
                } else {
                    text.push_str("0 Tr\n");
                }
            }
            current = Some(placed.style);
        }
        let x = geometry.x(placed.column);
        let y = geometry.baseline_y(placed.row);
        let shear =
            if custom_font.is_some() && matches!(placed.style, Style::Italic | Style::BoldItalic) {
                "0.21256"
            } else {
                "0"
            };
        let _ = write!(text, "1 0 {shear} 1 {} {} Tm <", number(x), number(y));
        for character in placed.text.chars() {
            let _ = write!(
                text,
                "{:04X}",
                font.glyphs.get(&character).copied().unwrap_or(0)
            );
        }
        text.push_str("> Tj\n");

        if placed.underline {
            // Under the baseline by the amount the face itself specifies, so
            // that the rule sits where the type designer put it rather than
            // where the renderer guessed.
            let (offset, thickness) = if let Some(ref metrics) = custom_underline {
                *metrics
            } else {
                *vendored_underline.entry(placed.style).or_insert_with(|| {
                    let face = Face::parse(placed.style.face().bytes);
                    let scale = BODY_FONT_POINTS / f64::from(face.units_per_em);
                    (
                        f64::from(face.underline_position) * scale,
                        f64::from(face.underline_thickness) * scale,
                    )
                })
            };
            let end = x + placed.text.chars().count() as f64 * geometry.column;
            let _ = writeln!(
                rules,
                "{} w {} {} m {} {} l S",
                number(thickness),
                number(x),
                number(y + offset),
                number(end),
                number(y + offset),
            );
        }
    }
    text.push_str("ET\n");
    text.push_str(&rules);
    text.into_bytes()
}

/// The document `/ID`.
///
/// The format asks for something unique per file, and every other producer
/// answers with a random number or a clock. §Phase 7 asks instead for a *fixed*
/// one, so this is a digest of what the file says: two exports of one script are
/// the same document and say so, and two different scripts do not collide.
fn identifier(
    script: &PaginatedScript,
    info: &DocumentInfo,
    config: &PageConfig,
    custom_font: Option<&[u8]>,
) -> [u8; 16] {
    let mut seed = script.debug_dump();
    seed.push_str(&format!(
        "\n{}\n{}\n{}\n{:?}\n{}\n",
        info.title,
        info.author,
        info.created_epoch_seconds,
        config.page_size,
        config.lines_per_page(),
    ));
    let mut bytes = seed.into_bytes();
    if let Some(font) = custom_font {
        bytes.extend_from_slice(font);
    }
    let digest = sha256::digest(&bytes);
    let mut id = [0u8; 16];
    id.copy_from_slice(&digest[..16]);
    id
}

#[cfg(test)]
mod tests {
    use super::*;
    use slugline_document::Document;
    use slugline_layout::paginate;

    fn info() -> DocumentInfo {
        DocumentInfo {
            title: "Test".to_owned(),
            author: "Writer".to_owned(),
            created_epoch_seconds: 1_700_000_000,
        }
    }

    fn export(source: &str, config: &PageConfig) -> Vec<u8> {
        render(&paginate(&Document::parse(source), config), config, &info())
    }

    #[test]
    fn geometry_puts_the_grid_where_section_5_2_says() {
        let letter = Geometry::of(&PageConfig::us_letter());
        assert_eq!(letter.width, 612.0);
        assert_eq!(letter.height, 792.0);
        // Column zero is the 1.5-inch text-area edge, and column 60 is 7.5.
        assert_eq!(letter.x(0), 108.0);
        assert_eq!(letter.x(60), 540.0);
        // Six lines to the inch, from a one-inch top margin.
        assert_eq!(letter.baseline_y(0) - letter.baseline_y(1), 12.0);
        assert_eq!(letter.baseline_y(0), 792.0 - 72.0 - 9.375);
        // The page number's row is half an inch above the text origin.
        assert_eq!(letter.baseline_y(-3), letter.baseline_y(0) + 36.0);

        let a4 = Geometry::of(&PageConfig::a4());
        assert_eq!(number(a4.width), "595.2756");
        assert_eq!(number(a4.height), "841.8898");
        assert_eq!(a4.x(0), 108.0, "A4 uses the same character grid (§5.2)");
    }

    #[test]
    fn a_title_page_is_the_first_sheet_and_is_not_numbered() {
        let document = Document::parse(
            "Title: Heat\nAuthor: Michael Mann\n\nINT. HOUSE - DAY\n\nJohn enters.\n",
        );
        let script = paginate(&document, &PageConfig::us_letter());
        let sheets = place(&script);

        assert_eq!(sheets.len(), script.pages.len() + 1);
        assert!(
            sheets[0].iter().any(|placed| placed.text.contains("Heat")),
            "the title is on the first sheet"
        );
        assert!(
            !sheets[0].iter().any(|placed| placed.text == "1."),
            "which carries no page number"
        );
        assert!(
            sheets[1].iter().any(|placed| placed.text == "1."),
            "the first screenplay page is still page 1"
        );
    }

    #[test]
    fn emphasis_chooses_the_face_and_the_markers_are_not_printed() {
        let script = paginate(
            &Document::parse("He reads *quietly* and **loudly** and _underlined_.\n"),
            &PageConfig::us_letter(),
        );
        let placed = place(&script).remove(0);
        let styled: Vec<(&str, Style, bool)> = placed
            .iter()
            .map(|p| (p.text.as_str(), p.style, p.underline))
            .collect();

        assert!(styled.contains(&("quietly", Style::Italic, false)));
        assert!(styled.contains(&("loudly", Style::Bold, false)));
        assert!(styled.contains(&("underlined", Style::Regular, true)));
        assert!(
            placed
                .iter()
                .all(|p| !p.text.contains('*') && !p.text.contains('_')),
            "no marker reaches the page"
        );
    }

    #[test]
    fn an_emphasis_run_the_paginator_wrapped_keeps_its_face_on_the_next_row() {
        // Long enough that the paginator must break it, and italic throughout.
        let long = "*".to_owned() + &"wandering ".repeat(12) + "home.*";
        let script = paginate(&Document::parse(&(long + "\n")), &PageConfig::us_letter());
        let placed = place(&script).remove(0);
        let rows: BTreeSet<i32> = placed
            .iter()
            .filter(|p| p.style == Style::Italic)
            .map(|p| p.row)
            .collect();

        assert!(rows.len() > 1, "the run wrapped onto more than one row");
        assert!(
            placed
                .iter()
                .filter(|p| !p.text.trim().is_empty() && p.text != "1.")
                .all(|p| p.style == Style::Italic),
            "and every row of it is italic"
        );
    }

    #[test]
    fn a_new_block_starts_plain_however_the_last_one_ended() {
        // An unclosed marker must not italicise the rest of the screenplay.
        let script = paginate(
            &Document::parse("He opens *emphasis and never closes it.\n\nThe next paragraph.\n"),
            &PageConfig::us_letter(),
        );
        let placed = place(&script).remove(0);
        let next = placed
            .iter()
            .find(|p| p.text.contains("next paragraph"))
            .expect("the second paragraph is on the page");
        assert_eq!(next.style, Style::Regular);
    }

    #[test]
    fn the_bytes_are_a_pdf_that_names_its_pages() {
        let bytes = export(
            "Title: Heat\n\nINT. HOUSE - DAY\n\nJohn enters.\n",
            &PageConfig::us_letter(),
        );
        let text = String::from_utf8_lossy(&bytes);
        assert!(text.starts_with("%PDF-1.7"));
        assert!(text.trim_end().ends_with("%%EOF"));
        assert_eq!(
            text.matches("/Type /Page\n").count() + text.matches("/Type /Page ").count(),
            2
        );
        assert!(text.contains("/Type /Catalog"));
        assert!(text.contains("/Subtype /CIDFontType2"));
        assert!(text.contains("/Encoding /Identity-H"));
        assert!(text.contains("/FontFile2"));
        assert!(text.contains("/ToUnicode"));
        assert!(text.contains("/MediaBox [0 0 612 792]"));
    }

    #[test]
    fn only_the_faces_a_script_uses_are_embedded() {
        let plain = export("Just action.\n", &PageConfig::us_letter());
        let mixed = export("Just *action*.\n", &PageConfig::us_letter());
        let count = |bytes: &[u8]| String::from_utf8_lossy(bytes).matches("/FontFile2").count();

        assert_eq!(count(&plain), 1, "one face for an unemphasised script");
        assert_eq!(count(&mixed), 2, "and a second only once italic is used");
    }

    #[test]
    fn the_same_script_renders_to_the_same_bytes() {
        let source = "Title: Heat\n\nINT. HOUSE - DAY\n\nJohn enters, *quietly*.\n\nJOHN\nHello.\n";
        let once = export(source, &PageConfig::us_letter());
        let twice = export(source, &PageConfig::us_letter());
        assert_eq!(once, twice);
        // And nothing about the file depends on the process it was made in.
        assert_eq!(sha256::hex(&once), sha256::hex(&twice));
    }

    #[test]
    fn a_selected_true_type_font_is_embedded_deterministically() {
        let config = PageConfig::us_letter();
        let script = paginate(&Document::parse("Custom face.\n"), &config);
        let once = render_with_font(&script, &config, &info(), fonts::REGULAR.bytes)
            .expect("vendored TrueType is a valid stand-in for a system face");
        let twice = render_with_font(&script, &config, &info(), fonts::REGULAR.bytes)
            .expect("the same face remains valid");

        assert_eq!(once, twice);
        assert!(String::from_utf8_lossy(&once).contains("SluglineSystemMonospace"));
        assert_ne!(once, render(&script, &config, &info()));
    }

    #[test]
    fn malformed_selected_font_is_a_failure_not_a_process_panic() {
        let config = PageConfig::us_letter();
        let script = paginate(&Document::parse("Action.\n"), &config);
        assert!(render_with_font(&script, &config, &info(), b"not a font").is_err());
    }

    #[test]
    fn the_timestamp_is_the_only_thing_that_can_move_and_it_is_an_argument() {
        let script = paginate(&Document::parse("Action.\n"), &PageConfig::us_letter());
        let config = PageConfig::us_letter();
        let early = render(
            &script,
            &config,
            &DocumentInfo {
                created_epoch_seconds: 0,
                ..info()
            },
        );
        let late = render(&script, &config, &info());
        assert_ne!(early, late);
        assert!(String::from_utf8_lossy(&early).contains("D:19700101000000+00'00'"));
    }

    #[test]
    fn source_date_epoch_overrides_the_clock() {
        // Serialised against nothing else: the variable is process-wide, and
        // this is the only test that touches it.
        std::env::set_var("SOURCE_DATE_EPOCH", "1700000000");
        assert_eq!(creation_time(), 1_700_000_000);
        std::env::set_var("SOURCE_DATE_EPOCH", "not a number");
        assert!(
            creation_time() > 1_700_000_000,
            "nonsense falls back to the clock"
        );
        std::env::remove_var("SOURCE_DATE_EPOCH");
    }

    #[test]
    fn a4_is_a_different_page_and_says_so() {
        let bytes = export("Action.\n", &PageConfig::a4());
        assert!(String::from_utf8_lossy(&bytes).contains("/MediaBox [0 0 595.2756 841.8898]"));
    }

    #[test]
    fn a_character_the_face_does_not_have_is_notdef_rather_than_a_panic() {
        let bytes = export("A clapperboard 🎬 and 日本.\n", &PageConfig::us_letter());
        assert!(bytes.starts_with(b"%PDF-1.7"));
    }
}
