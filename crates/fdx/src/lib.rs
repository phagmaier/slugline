//! Secure, syntax-only FDX interchange. Fountain remains the native format.
mod styles;

use quick_xml::{
    events::{BytesStart, Event},
    Reader,
};
use slugline_fountain::{
    BlockKind, Element, ElementRef, Emphasis, EmphasisRun, Script, TitleEntry, TitleField,
    TitlePage,
};
use std::{borrow::Cow, collections::HashMap, fmt};

#[derive(Debug)]
pub struct ImportedScript {
    pub script: Script,
    pub warnings: Vec<String>,
}
#[derive(Debug)]
pub struct ExportedScript {
    pub xml: String,
    pub warnings: Vec<String>,
}
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Error {
    message: String,
}
impl Error {
    fn new(message: impl Into<String>) -> Self {
        Self {
            message: message.into(),
        }
    }
}
impl fmt::Display for Error {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str(&self.message)
    }
}
impl std::error::Error for Error {}
fn xml_error(error: impl fmt::Display) -> Error {
    Error::new(format!("Invalid FDX XML: {error}"))
}
fn warn(warnings: &mut Vec<String>, message: impl Into<String>) {
    let message = message.into();
    if !warnings.contains(&message) {
        warnings.push(message);
    }
}
fn valid_xml(text: &str) -> Result<(), Error> {
    if text.chars().any(|c| !matches!(c, '\t' | '\n' | '\r' | '\u{20}'..='\u{d7ff}' | '\u{e000}'..='\u{fffd}' | '\u{10000}'..='\u{10ffff}')) {
        return Err(Error::new("Text contains a character XML 1.0 cannot represent."));
    }
    Ok(())
}
#[derive(Clone, Copy, PartialEq, Eq)]
enum Encoding {
    Utf8,
    Utf16Le,
    Utf16Be,
}
fn decode(bytes: &[u8]) -> Result<(Cow<'_, str>, Encoding), Error> {
    let encoding = if bytes.starts_with(&[0xff, 0xfe]) {
        Encoding::Utf16Le
    } else if bytes.starts_with(&[0xfe, 0xff]) {
        Encoding::Utf16Be
    } else {
        Encoding::Utf8
    };
    if encoding == Encoding::Utf8 {
        let bytes = bytes.strip_prefix(&[0xef, 0xbb, 0xbf]).unwrap_or(bytes);
        return Ok((
            Cow::Borrowed(std::str::from_utf8(bytes).map_err(xml_error)?),
            encoding,
        ));
    }
    if bytes.len() % 2 != 0 {
        return Err(Error::new("Truncated BOM-marked UTF-16 FDX."));
    }
    let words = bytes[2..].chunks_exact(2).map(|pair| {
        if encoding == Encoding::Utf16Le {
            u16::from_le_bytes([pair[0], pair[1]])
        } else {
            u16::from_be_bytes([pair[0], pair[1]])
        }
    });
    let mut decoded = String::with_capacity(bytes.len() / 2);
    for c in char::decode_utf16(words) {
        decoded.push(c.map_err(xml_error)?);
    }
    Ok((Cow::Owned(decoded), encoding))
}

type Attributes = Vec<(String, String)>;
fn attrs(start: &BytesStart<'_>) -> Result<Attributes, Error> {
    start
        .attributes()
        .map(|attribute| {
            let attribute = attribute.map_err(xml_error)?;
            let key = std::str::from_utf8(attribute.key.as_ref())
                .map_err(xml_error)?
                .to_owned();
            let value = attribute.unescape_value().map_err(xml_error)?.into_owned();
            valid_xml(&value)?;
            Ok((key, value))
        })
        .collect()
}
fn attr<'a>(attrs: &'a Attributes, key: &str) -> Option<&'a str> {
    attrs
        .iter()
        .find(|(name, _)| name == key)
        .map(|(_, value)| value.as_str())
}
fn flag(attrs: &Attributes, key: &str) -> Result<bool, Error> {
    match attr(attrs, key) {
        None | Some("No" | "false" | "0") => Ok(false),
        Some("Yes" | "true" | "1") => Ok(true),
        Some(value) => Err(Error::new(format!("Invalid {key} value {value:?}."))),
    }
}
#[derive(Default)]
struct Paragraph {
    attrs: Attributes,
    runs: Vec<EmphasisRun>,
    title: bool,
    note: bool,
    header_footer: Option<&'static str>,
    page_number: bool,
}
fn element(kind: BlockKind, text: String, dual: bool) -> Element {
    Element {
        kind,
        text,
        dual,
        forced: true,
        provenance: None,
    }
}
fn semantic_kind(value: &str) -> Option<BlockKind> {
    Some(match value {
        "SceneHeading" => BlockKind::SceneHeading,
        "Action" => BlockKind::Action,
        "Character" => BlockKind::Character,
        "Dialogue" => BlockKind::Dialogue,
        "Parenthetical" => BlockKind::Parenthetical,
        "Transition" => BlockKind::Transition,
        "Centered" => BlockKind::Centered,
        "Lyric" => BlockKind::Lyric,
        "Synopsis" => BlockKind::Synopsis,
        "Note" => BlockKind::Note,
        "PageBreak" => BlockKind::PageBreak,
        "Opaque" => BlockKind::Opaque,
        value if value.starts_with("Section:") => BlockKind::Section {
            level: value[8..].parse().ok()?,
        },
        _ => return None,
    })
}
fn check_semantics(kind: BlockKind, text: &str, dual: bool) -> Result<(), Error> {
    if (dual && kind != BlockKind::Character)
        || (kind == BlockKind::PageBreak && !text.is_empty())
        || matches!(kind, BlockKind::Section { level } if !(1..=6).contains(&level))
        || (!kind.is_multiline() && text.contains(['\n', '\r']))
        || (kind == BlockKind::Character && !dual && text.ends_with('^'))
        || (kind != BlockKind::Opaque && text.split('\n').any(|line| line.ends_with('\r')))
    {
        return Err(Error::new(format!(
            "Unrepresentable screenplay semantics for {kind:?}; text was not discarded."
        )));
    }
    Ok(())
}
fn finish(
    paragraph: Paragraph,
    script: &mut Script,
    warnings: &mut Vec<String>,
) -> Result<(), Error> {
    if paragraph.note {
        if paragraph.header_footer.is_some()
            && (paragraph.runs.is_empty()
                || (paragraph.page_number
                    && paragraph
                        .runs
                        .iter()
                        .flat_map(|run| run.text.chars())
                        .eq(".".chars())))
        {
            warn(warnings, "Empty header/footer and dynamic page-number formatting are layout, not imported screenplay content.");
            return Ok(());
        }
        warn(warnings, "Authored script notes/header/footer text retained as nonprinting Notes; original annotation placement and dynamic layout are not retained.");
        let text = styles::markup(&paragraph.runs, warnings);
        let text = if let Some(label) = paragraph.header_footer {
            format!("FDX {label}: {text}")
        } else {
            text
        };
        script.elements.push(element(BlockKind::Note, text, false));
        return Ok(());
    }
    if paragraph.title {
        let plain = styles::text(&paragraph.runs);
        if paragraph.runs.is_empty() && attr(&paragraph.attrs, "SluglineTitleField").is_none() {
            // Empty positional paragraphs are title-page layout, not user text.
            return Ok(());
        }
        let field = if let Some(key) = attr(&paragraph.attrs, "SluglineTitleField") {
            TitleField::from_key(key)
        } else {
            let alignment = attr(&paragraph.attrs, "Alignment").unwrap_or("");
            let credit = plain.trim().to_ascii_lowercase();
            if alignment == "Center"
                && matches!(credit.as_str(), "written by" | "by" | "screenplay by")
            {
                TitleField::Credit
            } else if alignment == "Center"
                && script
                    .title_page
                    .entries
                    .last()
                    .is_some_and(|e| matches!(e.field, TitleField::Credit | TitleField::Author))
            {
                TitleField::Author
            } else if alignment == "Center"
                && (script.title_page.get(&TitleField::Title).is_none()
                    || script
                        .title_page
                        .entries
                        .last()
                        .is_some_and(|e| e.field == TitleField::Title))
            {
                TitleField::Title
            } else {
                warn(warnings, "Unmatched positional title-page text retained in Notes; title layout is not imported.");
                TitleField::Notes
            }
        };
        let value = if let Some(raw) = attr(&paragraph.attrs, "SluglineRaw") {
            if !styles::equivalent(&styles::printable_title(raw), &paragraph.runs) {
                return Err(Error::new(
                    "Title metadata disagrees with visible text/styles.",
                ));
            }
            raw.to_owned()
        } else {
            styles::markup(&paragraph.runs, warnings)
        };
        if attr(&paragraph.attrs, "SluglineTitleField").is_none() {
            if let Some(previous) = script.title_page.entries.last_mut().filter(|e| {
                e.field == field && matches!(field, TitleField::Title | TitleField::Author)
            }) {
                previous.value.push('\n');
                previous.value.push_str(&value);
                return Ok(());
            }
        }
        script.title_page.entries.push(TitleEntry { field, value });
        return Ok(());
    }
    let metadata = attr(&paragraph.attrs, "SluglineKind");
    if metadata.is_none() && attr(&paragraph.attrs, "SluglineRaw").is_some() {
        return Err(Error::new(
            "SluglineRaw without SluglineKind is unsupported; visible text was not discarded.",
        ));
    }
    let mut kind = match attr(&paragraph.attrs, "Type").unwrap_or("") {
        "Scene Heading" => BlockKind::SceneHeading,
        "Action" => {
            if attr(&paragraph.attrs, "Alignment") == Some("Center") {
                BlockKind::Centered
            } else {
                BlockKind::Action
            }
        }
        "Character" => BlockKind::Character,
        "Dialogue" => BlockKind::Dialogue,
        "Parenthetical" => BlockKind::Parenthetical,
        "Transition" => BlockKind::Transition,
        "Lyrics" | "Lyric" => BlockKind::Lyric,
        value => {
            warn(
                warnings,
                format!("Unsupported paragraph type {value:?} retained as Action."),
            );
            BlockKind::Action
        }
    };
    let mut text = String::new();
    let mut dual = false;
    let mut forced = true;
    if let Some(value) = metadata {
        let visible_kind = kind;
        kind = semantic_kind(value)
            .ok_or_else(|| Error::new(format!("Unknown SluglineKind {value:?}.")))?;
        let visible_metadata_kind = match kind {
            BlockKind::Section { .. }
            | BlockKind::Synopsis
            | BlockKind::Note
            | BlockKind::Opaque
            | BlockKind::PageBreak => BlockKind::Action,
            _ => kind,
        };
        if visible_kind != visible_metadata_kind
            || (kind == BlockKind::PageBreak && !flag(&paragraph.attrs, "StartsNewPage")?)
        {
            return Err(Error::new(
                "Slugline paragraph metadata disagrees with its visible kind or page break.",
            ));
        }
        if let Some(raw) = attr(&paragraph.attrs, "SluglineRaw") {
            let agrees = if matches!(
                kind,
                BlockKind::Opaque
                    | BlockKind::Note
                    | BlockKind::Synopsis
                    | BlockKind::Section { .. }
            ) {
                paragraph
                    .runs
                    .iter()
                    .all(|run| run.emphasis == Emphasis::PLAIN)
                    && paragraph
                        .runs
                        .iter()
                        .flat_map(|run| run.text.chars())
                        .eq(raw.chars())
            } else {
                let expected = if kind == BlockKind::SceneHeading {
                    styles::printable(slugline_fountain::split_scene_number(raw).0)
                } else {
                    styles::printable(raw)
                };
                styles::equivalent(&expected, &paragraph.runs)
            };
            if !agrees {
                return Err(Error::new(
                    "Slugline paragraph metadata disagrees with visible text/styles.",
                ));
            }
            if kind == BlockKind::SceneHeading
                && slugline_fountain::split_scene_number(raw).1 != attr(&paragraph.attrs, "Number")
            {
                return Err(Error::new(
                    "Slugline scene metadata disagrees with its scene number.",
                ));
            }
            text = raw.to_owned();
        }
        dual = flag(&paragraph.attrs, "SluglineDual")?;
        forced = flag(&paragraph.attrs, "SluglineForced")?;
    }
    if attr(&paragraph.attrs, "SluglineRaw").is_none() {
        text = if metadata.is_some()
            && matches!(
                kind,
                BlockKind::Opaque
                    | BlockKind::Note
                    | BlockKind::Synopsis
                    | BlockKind::Section { .. }
            ) {
            if paragraph
                .runs
                .iter()
                .any(|run| run.emphasis != Emphasis::PLAIN)
            {
                warn(warnings, "Styles on metadata-backed nonprinting content flattened to literal text; all annotation/outline/omitted words retained.");
            }
            styles::text(&paragraph.runs)
        } else {
            styles::markup(&paragraph.runs, warnings)
        };
        if kind == BlockKind::SceneHeading {
            if let Some(number) = attr(&paragraph.attrs, "Number") {
                let candidate = format!("{text} #{number}#");
                if slugline_fountain::split_scene_number(&candidate).1 != Some(number) {
                    return Err(Error::new(
                        "Scene number cannot be represented by Fountain's scene-number syntax.",
                    ));
                }
                text = candidate;
            }
        }
    }
    if metadata.is_none() {
        if text.contains("[[") {
            return Err(Error::new("Literal XML [[ text cannot be represented as printable Fountain text without becoming a hidden note; import refused to retain its meaning."));
        }
        if matches!(kind, BlockKind::Centered | BlockKind::Lyric)
            && text.contains('\n')
            && !text.contains('\r')
        {
            warn(
                warnings,
                format!("Hard lines in {kind:?} retained as consecutive native {kind:?} elements."),
            );
            if flag(&paragraph.attrs, "StartsNewPage")? {
                script
                    .elements
                    .push(element(BlockKind::PageBreak, String::new(), false));
            }
            for line in text.split('\n') {
                script.elements.push(element(kind, line.to_owned(), false));
            }
            return Ok(());
        }
        if !kind.is_multiline() && text.contains(['\n', '\r']) {
            warn(warnings, format!("Hard lines in {kind:?} retained as Action because that Fountain kind is single-line."));
            kind = BlockKind::Action;
        }
        if kind == BlockKind::Character && text.ends_with('^') {
            warn(warnings, "Literal trailing caret in Character retained as Action, not interpreted as a dual marker.");
            kind = BlockKind::Action;
        }
    }
    check_semantics(kind, &text, dual)?;
    if flag(&paragraph.attrs, "StartsNewPage")? && metadata != Some("PageBreak") {
        script
            .elements
            .push(element(BlockKind::PageBreak, String::new(), false));
    }
    let mut value = element(kind, text, dual);
    value.forced = forced;
    script.elements.push(value);
    Ok(())
}

/// Normalize paragraph boundaries that Fountain's native body cannot store
/// separately, then prove that native save/reopen retains the same identities.
fn normalize(script: &mut Script, warnings: &mut Vec<String>) -> Result<(), Error> {
    // The native title form edits one value per key. Repeated FDX paragraphs
    // must not become duplicate native keys: that form shows and writes only
    // the first, leaving the later title words where no box reaches them.
    let entries = &mut script.title_page.entries;
    let mut first = HashMap::with_capacity(entries.len());
    let mut duplicates = Vec::new();
    for (index, entry) in entries.iter().enumerate() {
        if let Some(previous) = first.get(&entry.field) {
            duplicates.push((index, *previous));
        } else {
            first.insert(&entry.field, index);
        }
    }
    drop(first);
    for &(index, previous) in &duplicates {
        let (before, after) = entries.split_at_mut(index);
        before[previous].value.reserve(1 + after[0].value.len());
        before[previous].value.push('\n');
        before[previous].value.push_str(&after[0].value);
        warn(warnings, "Repeated title fields joined with hard lines so all authored words remain in one editable native field.");
    }
    let mut removed = duplicates.iter().map(|(index, _)| *index).peekable();
    let mut index = 0;
    entries.retain(|_| {
        let keep = removed.peek() != Some(&index);
        if !keep {
            removed.next();
        }
        index += 1;
        keep
    });
    let mut elements: Vec<Element> = Vec::with_capacity(script.elements.len());
    for value in std::mem::take(&mut script.elements) {
        if value.kind == BlockKind::Action && value.text.is_empty() {
            warn(
                warnings,
                "Empty Action/General spacer paragraphs normalized to native Fountain boundaries.",
            );
            continue;
        }
        if value.kind == BlockKind::Dialogue {
            if let Some(previous) = elements
                .last_mut()
                .filter(|e| e.kind == BlockKind::Dialogue)
            {
                previous.text.push('\n');
                previous.text.push_str(&value.text);
                warn(warnings, "Adjacent Dialogue paragraphs coalesced with a hard line to preserve native save/recovery boundaries.");
                continue;
            }
        }
        elements.push(value);
    }
    if elements.is_empty() {
        elements.push(element(BlockKind::Action, String::new(), false));
    }
    script.elements = elements;
    let refs: Vec<_> = script.elements.iter().map(Element::as_ref).collect();
    let canonical = slugline_fountain::serialise(&slugline_fountain::Output {
        title_page: &script.title_page,
        elements: &refs,
        source: None,
        bom: false,
        line_ending: script.line_ending,
    });
    let native = slugline_fountain::parse(&canonical);
    let compatible = script.elements.len() == native.elements.len()
        && script
            .elements
            .iter()
            .zip(&native.elements)
            .all(|(original, parsed)| {
                original.kind == parsed.kind
                    && original.dual == parsed.dual
                    && (original.text == parsed.text
                        || (original.kind == BlockKind::Opaque
                            && original.text.trim_end_matches('\n')
                                == parsed.text.trim_end_matches('\n')))
            });
    if !compatible {
        return Err(Error::new("FDX paragraph text/boundaries cannot be represented safely by native Fountain save/recovery; import refused rather than losing text or changing identities."));
    }
    if script.title_page.entries.len() != native.title_page.entries.len()
        || script
            .title_page
            .in_canonical_order()
            .into_iter()
            .zip(native.title_page.in_canonical_order())
            .any(|(original, parsed)| {
                original.field != parsed.field || original.value != parsed.value
            })
    {
        return Err(Error::new("FDX title text cannot be represented safely by native Fountain; import refused rather than losing title content."));
    }
    Ok(())
}

/// Reads UTF-8 or BOM-marked UTF-16 without I/O, entities or external resources.
pub fn read(bytes: &[u8]) -> Result<ImportedScript, Error> {
    let (source, encoding) = decode(bytes)?;
    valid_xml(&source)?;
    let mut reader = Reader::from_str(&source);
    reader.config_mut().enable_all_checks(true);
    let mut stack: Vec<String> = Vec::new();
    let mut paragraph: Option<Paragraph> = None;
    let mut suspended: Option<Paragraph> = None;
    let mut style = Emphasis::PLAIN;
    let mut script = Script::default();
    let mut warnings = Vec::new();
    let mut root_seen = false;
    let mut content_seen = false;
    let mut declaration_seen = false;
    let mut dual_start = None;
    loop {
        let event = reader.read_event().map_err(|e| {
            Error::new(format!(
                "Invalid FDX XML at byte {}: {e}",
                reader.error_position()
            ))
        })?;
        let empty = matches!(&event, Event::Empty(_));
        match event {
            Event::Decl(declaration) => {
                if declaration_seen || root_seen {
                    return Err(Error::new("Misplaced or repeated XML declaration."));
                }
                declaration_seen = true;
                if declaration.version().map_err(xml_error)?.as_ref() != b"1.0" {
                    return Err(Error::new("Only XML 1.0 is supported."));
                }
                if let Some(declared) = declaration.encoding() {
                    let declared = declared.map_err(xml_error)?;
                    let declared = std::str::from_utf8(&declared)
                        .map_err(xml_error)?
                        .to_ascii_lowercase();
                    let matches = match encoding {
                        Encoding::Utf8 => declared == "utf-8" || declared == "utf8",
                        Encoding::Utf16Le => declared == "utf-16" || declared == "utf-16le",
                        Encoding::Utf16Be => declared == "utf-16" || declared == "utf-16be",
                    };
                    if !matches {
                        return Err(Error::new(format!(
                            "Unsupported or BOM-mismatched encoding declaration {declared:?}."
                        )));
                    }
                }
                if let Some(standalone) = declaration.standalone() {
                    let standalone = standalone.map_err(xml_error)?;
                    if !matches!(standalone.as_ref(), b"yes" | b"no") {
                        return Err(Error::new("Invalid XML standalone declaration."));
                    }
                }
            }
            Event::DocType(_) => {
                return Err(Error::new("DTD/entity declarations are not supported."))
            }
            Event::PI(_) => return Err(Error::new("Processing instructions are not supported.")),
            Event::Start(start) | Event::Empty(start) => {
                let name = std::str::from_utf8(start.name().as_ref())
                    .map_err(xml_error)?
                    .to_owned();
                let attributes = attrs(&start)?;
                let parent = stack.last().map(String::as_str);
                if stack.get(1).is_some_and(|name| name == "SmartType") {
                    if !empty {
                        if stack.len() >= 128 {
                            return Err(Error::new(
                                "FDX nesting exceeds the supported structural depth.",
                            ));
                        }
                        stack.push(name);
                    }
                    continue;
                }
                if stack.is_empty() {
                    if root_seen || name != "FinalDraft" {
                        return Err(Error::new("Expected one FinalDraft document root."));
                    }
                    root_seen = true;
                    if attr(&attributes, "DocumentType").is_some_and(|value| value != "Script") {
                        return Err(Error::new("FDX document is not a screenplay Script."));
                    }
                } else if name == "Content" && parent == Some("FinalDraft") {
                    if content_seen {
                        return Err(Error::new("Repeated screenplay Content."));
                    }
                    content_seen = true;
                } else if name == "Paragraph" {
                    let allowed = (parent == Some("Content")
                        && (stack.len() == 2
                            || stack
                                .get(stack.len().saturating_sub(2))
                                .is_some_and(|name| name == "TitlePage")))
                        || parent == Some("DualDialogue")
                        || parent == Some("ScriptNote")
                        || (matches!(parent, Some("Header" | "Footer"))
                            && stack.iter().any(|name| name == "HeaderAndFooter"));
                    if !allowed || paragraph.is_some() {
                        return Err(Error::new("Unsupported nested Paragraph structure."));
                    }
                    let title = stack.iter().any(|name| name == "TitlePage");
                    let note =
                        parent == Some("ScriptNote") || matches!(parent, Some("Header" | "Footer"));
                    let header_footer = match parent {
                        Some("Header") => Some("Header"),
                        Some("Footer") => Some("Footer"),
                        _ => None,
                    };
                    paragraph = Some(Paragraph {
                        attrs: Vec::new(),
                        runs: Vec::new(),
                        title: title && !note,
                        note,
                        header_footer,
                        page_number: false,
                    });
                } else if name == "DualDialogue" {
                    if empty || parent != Some("Paragraph") || dual_start.is_some() {
                        return Err(Error::new("Invalid nested/empty DualDialogue wrapper."));
                    }
                    let wrapper = paragraph
                        .take()
                        .ok_or_else(|| Error::new("Missing dual wrapper Paragraph."))?;
                    if !wrapper.runs.is_empty() || wrapper.title {
                        return Err(Error::new("Dual wrapper contains unsupported text."));
                    }
                    dual_start = Some(script.elements.len());
                } else if name == "ScriptNote" && parent == Some("Paragraph") {
                    if empty || suspended.is_some() {
                        return Err(Error::new("Unsupported empty/nested ScriptNote."));
                    }
                    suspended = paragraph.take();
                    if suspended.is_none() {
                        return Err(Error::new("ScriptNote has no parent Paragraph."));
                    }
                } else if name == "SceneProperties" && parent == Some("Paragraph") {
                    if let Some(title) =
                        attr(&attributes, "Title").filter(|title| !title.is_empty())
                    {
                        script.elements.push(element(
                            BlockKind::Note,
                            styles::literal(title),
                            false,
                        ));
                        warn(&mut warnings, "SceneProperties title retained as a nonprinting Note; scene production metadata is not imported.");
                    }
                } else if name == "DynamicLabel"
                    && paragraph.as_ref().is_some_and(|p| p.note)
                    && empty
                {
                    warn(&mut warnings, "Dynamic header/footer label omitted as layout; literal header/footer text is retained in Notes.");
                    if attr(&attributes, "Type") == Some("Page #") {
                        if let Some(paragraph) = paragraph.as_mut() {
                            paragraph.page_number = true;
                        }
                    }
                } else if name == "Text" {
                    if parent != Some("Paragraph") || paragraph.is_none() {
                        return Err(Error::new("Text outside a screenplay/title Paragraph is unsupported; import refused to retain all text."));
                    }
                    style = Emphasis::PLAIN;
                    if let Some(value) = attr(&attributes, "Style") {
                        for token in value.split('+').map(str::trim) {
                            match token { "" | "Normal" => {}, "Bold" => style.bold = true,
                                "Italic" => style.italic = true, "Underline" => style.underline = true,
                                unknown => warn(&mut warnings, format!("Unsupported Text style {unknown:?} flattened; text retained.")), }
                        }
                    }
                    match attr(&attributes, "AdornmentStyle") {
                        Some("-1") => {
                            style.italic = true;
                            warn(&mut warnings, "AdornmentStyle=-1 normalized to italic.");
                        }
                        None | Some("" | "0") => {}
                        Some(value) => warn(
                            &mut warnings,
                            format!(
                                "Unsupported AdornmentStyle {value:?} flattened; text retained."
                            ),
                        ),
                    }
                } else if name == "LineBreak" && matches!(parent, Some("Text" | "Paragraph")) {
                    let paragraph = paragraph
                        .as_mut()
                        .ok_or_else(|| Error::new("LineBreak outside Paragraph."))?;
                    styles::push(&mut paragraph.runs, "\n", style);
                    if !empty {
                        return Err(Error::new("LineBreak must be empty."));
                    }
                } else {
                    if paragraph.is_some() {
                        return Err(Error::new(format!("Unsupported nested paragraph content {name:?}; import refused to retain all text.")));
                    }
                    if name == "SmartType" && parent == Some("FinalDraft") {
                        warn(&mut warnings, "SmartType completion caches/settings are not imported as authored screenplay content.");
                    } else if !matches!(name.as_str(), "TitlePage" | "Content")
                        && stack.get(1).is_none_or(|name| name != "SmartType")
                    {
                        warn(&mut warnings, format!("FDX production/layout structure {name:?} is not imported; textual content outside recognized paragraphs causes refusal."));
                    }
                }
                for (key, _) in &attributes {
                    let recognized = match name.as_str() {
                        "FinalDraft" => {
                            matches!(key.as_str(), "DocumentType" | "Template" | "Version")
                        }
                        "Paragraph" => matches!(
                            key.as_str(),
                            "Type"
                                | "Alignment"
                                | "Number"
                                | "StartsNewPage"
                                | "SpaceBefore"
                                | "SluglineKind"
                                | "SluglineRaw"
                                | "SluglineForced"
                                | "SluglineDual"
                                | "SluglineTitleField"
                        ),
                        "Text" => matches!(key.as_str(), "Style" | "AdornmentStyle"),
                        "SceneProperties" => parent == Some("Paragraph") && key == "Title",
                        _ => false,
                    };
                    if !recognized {
                        warn(&mut warnings, format!("FDX {name} attribute {key:?} is not imported (layout/production formatting)."));
                    }
                }
                if name == "Paragraph" {
                    paragraph
                        .as_mut()
                        .ok_or_else(|| Error::new("Missing Paragraph attributes."))?
                        .attrs = attributes;
                }
                if empty {
                    if name == "Paragraph" {
                        finish(
                            paragraph
                                .take()
                                .ok_or_else(|| Error::new("Empty nested Paragraph."))?,
                            &mut script,
                            &mut warnings,
                        )?;
                    }
                } else {
                    if stack.len() >= 128 {
                        return Err(Error::new(
                            "FDX nesting exceeds the supported structural depth.",
                        ));
                    }
                    stack.push(name);
                }
            }
            Event::End(end) => {
                let name = std::str::from_utf8(end.name().as_ref())
                    .map_err(xml_error)?
                    .to_owned();
                if stack.pop().as_deref() != Some(name.as_str()) {
                    return Err(Error::new("Mismatched XML closing element."));
                }
                if stack.get(1).is_some_and(|name| name == "SmartType") {
                    continue;
                }
                if name == "Paragraph" {
                    if let Some(value) = paragraph.take() {
                        finish(value, &mut script, &mut warnings)?;
                    }
                } else if name == "ScriptNote" {
                    if paragraph.is_some() {
                        return Err(Error::new("Unclosed ScriptNote Paragraph."));
                    }
                    paragraph = suspended.take();
                } else if name == "DualDialogue" {
                    let start = dual_start
                        .take()
                        .ok_or_else(|| Error::new("Missing dual group start."))?;
                    let group = &mut script.elements[start..];
                    let cues: Vec<_> = group
                        .iter()
                        .enumerate()
                        .filter(|(_, e)| e.kind == BlockKind::Character)
                        .map(|(i, _)| i)
                        .collect();
                    if cues.len() == 2
                        && cues[0] == 0
                        && cues[1] > 1
                        && cues[1] + 1 < group.len()
                        && group.iter().enumerate().all(|(i, e)| {
                            cues.contains(&i)
                                || matches!(e.kind, BlockKind::Dialogue | BlockKind::Parenthetical)
                        })
                    {
                        group[cues[1]].dual = true;
                    } else {
                        warn(&mut warnings, "Incomplete/unsupported DualDialogue retained in source order without inventing a partner.");
                    }
                }
            }
            Event::Text(text) => {
                if text.as_ref().windows(3).any(|bytes| bytes == b"]]>") {
                    return Err(Error::new(
                        "Invalid XML character data contains ]]> outside CDATA.",
                    ));
                }
                let text = text.xml10_content().map_err(xml_error)?;
                collect_text(&stack, &mut paragraph, &text, style)?;
            }
            Event::CData(text) => {
                let text = text.xml10_content().map_err(xml_error)?;
                collect_text(&stack, &mut paragraph, &text, style)?;
            }
            Event::GeneralRef(reference) => {
                let value = if let Some(c) = reference.resolve_char_ref().map_err(xml_error)? {
                    c.to_string()
                } else {
                    match reference.as_ref() {
                        b"amp" => "&",
                        b"lt" => "<",
                        b"gt" => ">",
                        b"quot" => "\"",
                        b"apos" => "'",
                        _ => {
                            return Err(Error::new(
                                "Custom/external XML entity references are not supported.",
                            ))
                        }
                    }
                    .to_owned()
                };
                valid_xml(&value)?;
                collect_text(&stack, &mut paragraph, &value, style)?;
            }
            Event::Comment(_) => {}
            Event::Eof => break,
        }
    }
    if !root_seen
        || !content_seen
        || !stack.is_empty()
        || paragraph.is_some()
        || dual_start.is_some()
        || suspended.is_some()
    {
        return Err(Error::new("Incomplete FDX screenplay document."));
    }
    normalize(&mut script, &mut warnings)?;
    Ok(ImportedScript { script, warnings })
}
fn collect_text(
    stack: &[String],
    paragraph: &mut Option<Paragraph>,
    text: &str,
    style: Emphasis,
) -> Result<(), Error> {
    if stack.get(1).is_some_and(|name| name == "SmartType") {
        // Recognized completion settings are not authored content. The owning
        // SmartType start event reports this excluded production profile.
    } else if stack.last().is_some_and(|name| name == "Text") {
        styles::push(
            &mut paragraph
                .as_mut()
                .ok_or_else(|| Error::new("Text has no Paragraph."))?
                .runs,
            text,
            style,
        );
    } else if !text.trim().is_empty() {
        return Err(Error::new(format!(
            "Unsupported text inside {:?}; import refused rather than discarding it.",
            stack.last()
        )));
    }
    Ok(())
}

fn escape_into(xml: &mut String, text: &str, attribute: bool) -> Result<(), Error> {
    for c in text.chars() {
        match c {
            '&' => xml.push_str("&amp;"),
            '<' => xml.push_str("&lt;"),
            '>' => xml.push_str("&gt;"),
            '"' => xml.push_str("&quot;"),
            '\'' => xml.push_str("&apos;"),
            '\r' => xml.push_str("&#13;"),
            '\n' if attribute => xml.push_str("&#10;"),
            '\t' if attribute => xml.push_str("&#9;"),
            '\t'
            | '\n'
            | '\u{20}'..='\u{d7ff}'
            | '\u{e000}'..='\u{fffd}'
            | '\u{10000}'..='\u{10ffff}' => xml.push(c),
            _ => {
                return Err(Error::new(
                    "Text contains a character XML 1.0 cannot represent.",
                ))
            }
        }
    }
    Ok(())
}
fn attribute(xml: &mut String, key: &str, value: &str) -> Result<(), Error> {
    xml.push(' ');
    xml.push_str(key);
    xml.push_str("=\"");
    escape_into(xml, value, true)?;
    xml.push('"');
    Ok(())
}
fn emit_runs(xml: &mut String, runs: &[EmphasisRun]) -> Result<(), Error> {
    if runs.is_empty() {
        xml.push_str("<Text></Text>");
    }
    for run in runs {
        xml.push_str("<Text");
        let style = match (
            run.emphasis.bold,
            run.emphasis.italic,
            run.emphasis.underline,
        ) {
            (false, false, false) => "",
            (true, false, false) => "Bold",
            (false, true, false) => "Italic",
            (false, false, true) => "Underline",
            (true, true, false) => "Bold+Italic",
            (true, false, true) => "Bold+Underline",
            (false, true, true) => "Italic+Underline",
            (true, true, true) => "Bold+Italic+Underline",
        };
        if !style.is_empty() {
            attribute(xml, "Style", style)?;
        }
        xml.push('>');
        escape_into(xml, &run.text, false)?;
        xml.push_str("</Text>");
    }
    Ok(())
}
fn emit_element(
    xml: &mut String,
    e: &ElementRef<'_>,
    warnings: &mut Vec<String>,
) -> Result<(), Error> {
    check_semantics(e.kind, e.text, e.dual)?;
    let kind_name: Cow<'_, str> = match e.kind {
        BlockKind::SceneHeading => "SceneHeading".into(),
        BlockKind::Action => "Action".into(),
        BlockKind::Character => "Character".into(),
        BlockKind::Dialogue => "Dialogue".into(),
        BlockKind::Parenthetical => "Parenthetical".into(),
        BlockKind::Transition => "Transition".into(),
        BlockKind::Centered => "Centered".into(),
        BlockKind::Lyric => "Lyric".into(),
        BlockKind::Section { level } => format!("Section:{level}").into(),
        BlockKind::Synopsis => "Synopsis".into(),
        BlockKind::Note => "Note".into(),
        BlockKind::PageBreak => "PageBreak".into(),
        BlockKind::Opaque => "Opaque".into(),
    };
    let paragraph_type = match e.kind {
        BlockKind::SceneHeading => "Scene Heading",
        BlockKind::Character => "Character",
        BlockKind::Dialogue => "Dialogue",
        BlockKind::Parenthetical => "Parenthetical",
        BlockKind::Transition => "Transition",
        BlockKind::Lyric => "Lyrics",
        _ => "Action",
    };
    xml.push_str("<Paragraph");
    attribute(xml, "Type", paragraph_type)?;
    attribute(xml, "SluglineKind", &kind_name)?;
    attribute(xml, "SluglineForced", if e.forced { "Yes" } else { "No" })?;
    attribute(xml, "SluglineDual", if e.dual { "Yes" } else { "No" })?;
    if e.kind == BlockKind::Centered {
        attribute(xml, "Alignment", "Center")?;
    }
    if e.kind == BlockKind::PageBreak {
        attribute(xml, "StartsNewPage", "Yes")?;
    }
    let raw = if e.kind == BlockKind::SceneHeading {
        let (text, number) = slugline_fountain::split_scene_number(e.text);
        if let Some(number) = number {
            attribute(xml, "Number", number)?;
        }
        text
    } else {
        e.text
    };
    let nonprinting = matches!(
        e.kind,
        BlockKind::Section { .. } | BlockKind::Synopsis | BlockKind::Note | BlockKind::Opaque
    );
    let runs = if nonprinting {
        Vec::new()
    } else {
        styles::printable(raw)
    };
    // Nonprinting raw text already lives in Text and needs only its kind.
    // Extra raw metadata is for inline hidden semantics/unrepresentable pairing.
    let canonical = if nonprinting {
        String::new()
    } else {
        styles::markup(&runs, warnings)
    };
    if !nonprinting
        && (raw.contains("[[")
            || raw.contains("/*")
            || !styles::equivalent(&runs, &styles::printable(&canonical)))
    {
        attribute(xml, "SluglineRaw", e.text)?;
    }
    xml.push('>');
    if nonprinting {
        warn(warnings, format!("Nonprinting {kind_name} (including notes/omitted text) becomes visible Action text to the recipient; Slugline metadata retains original semantics only for Slugline re-import."));
    } else if raw.contains("[[") || raw.contains("/*") {
        warn(warnings, "Inline notes/boneyards become visible text to the recipient, not hidden annotations; original Fountain text retained only for Slugline re-import.");
    }
    if nonprinting {
        xml.push_str("<Text>");
        escape_into(xml, raw, false)?;
        xml.push_str("</Text>");
    } else {
        emit_runs(xml, &runs)?;
    }
    xml.push_str("</Paragraph>\n");
    Ok(())
}
fn speech_end(elements: &[ElementRef<'_>], start: usize) -> Option<usize> {
    if elements.get(start)?.kind != BlockKind::Character {
        return None;
    }
    let mut end = start + 1;
    while elements
        .get(end)
        .is_some_and(|e| matches!(e.kind, BlockKind::Dialogue | BlockKind::Parenthetical))
    {
        end += 1;
    }
    (end > start + 1).then_some(end)
}

// Finite paragraph bounds are part of an interoperable FDX file, not a copy of
// Slugline's pagination. Fade In imports words but paints ordinary paragraphs
// blank without these definitions; supplying Text fonts alone does not fix it.
const ELEMENT_SETTINGS: &str = concat!(
    "<ElementSettings Type=\"Scene Heading\"><ParagraphSpec FirstIndent=\"0.00\" Leading=\"Regular\" Alignment=\"Left\" LeftIndent=\"1.25\" RightIndent=\"7.25\" SpaceBefore=\"24\" Spacing=\"1.0\" StartsNewPage=\"No\"/></ElementSettings>\n",
    "<ElementSettings Type=\"Action\"><ParagraphSpec FirstIndent=\"0.00\" Leading=\"Regular\" Alignment=\"Left\" LeftIndent=\"1.25\" RightIndent=\"7.25\" SpaceBefore=\"12\" Spacing=\"1.0\" StartsNewPage=\"No\"/></ElementSettings>\n",
    "<ElementSettings Type=\"Character\"><ParagraphSpec FirstIndent=\"0.00\" Leading=\"Regular\" Alignment=\"Left\" LeftIndent=\"3.75\" RightIndent=\"7.25\" SpaceBefore=\"12\" Spacing=\"1.0\" StartsNewPage=\"No\"/></ElementSettings>\n",
    "<ElementSettings Type=\"Parenthetical\"><ParagraphSpec FirstIndent=\"-0.10\" Leading=\"Regular\" Alignment=\"Left\" LeftIndent=\"3.25\" RightIndent=\"5.25\" SpaceBefore=\"0\" Spacing=\"1.0\" StartsNewPage=\"No\"/></ElementSettings>\n",
    "<ElementSettings Type=\"Dialogue\"><ParagraphSpec FirstIndent=\"0.00\" Leading=\"Regular\" Alignment=\"Left\" LeftIndent=\"2.55\" RightIndent=\"6.25\" SpaceBefore=\"0\" Spacing=\"1.0\" StartsNewPage=\"No\"/></ElementSettings>\n",
    "<ElementSettings Type=\"Transition\"><ParagraphSpec FirstIndent=\"0.00\" Leading=\"Regular\" Alignment=\"Right\" LeftIndent=\"5.25\" RightIndent=\"6.75\" SpaceBefore=\"12\" Spacing=\"1.0\" StartsNewPage=\"No\"/></ElementSettings>\n",
    "<ElementSettings Type=\"Lyrics\"><ParagraphSpec FirstIndent=\"0.00\" Leading=\"Regular\" Alignment=\"Left\" LeftIndent=\"1.25\" RightIndent=\"7.25\" SpaceBefore=\"12\" Spacing=\"1.0\" StartsNewPage=\"No\"/></ElementSettings>\n",
);
/// Writes a deterministic editable FDX copy. Warnings must be approved before I/O.
pub fn write<'a>(
    title_page: &TitlePage,
    elements: impl IntoIterator<Item = ElementRef<'a>>,
) -> Result<ExportedScript, Error> {
    let elements: Vec<_> = elements.into_iter().collect();
    let mut xml = String::from("<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<FinalDraft DocumentType=\"Script\" Template=\"No\" Version=\"1\">\n<Content>\n");
    let mut warnings = Vec::new();
    let mut index = 0;
    while index < elements.len() {
        let pair_end = speech_end(&elements, index).and_then(|second| {
            if elements.get(second).is_some_and(|e| e.dual) {
                speech_end(&elements, second)
            } else {
                None
            }
        });
        if let Some(end) = pair_end {
            xml.push_str("<Paragraph><DualDialogue>\n");
            for e in &elements[index..end] {
                emit_element(&mut xml, e, &mut warnings)?;
            }
            xml.push_str("</DualDialogue></Paragraph>\n");
            index = end;
        } else {
            if elements[index].dual {
                warn(&mut warnings, "Orphan dual-dialogue cue exported as an ordinary speech; its marker is retained in Slugline metadata.");
            }
            emit_element(&mut xml, &elements[index], &mut warnings)?;
            index += 1;
        }
    }
    xml.push_str("</Content>\n");
    if !title_page.is_empty() {
        xml.push_str("<TitlePage><Content>\n");
        for entry in title_page.in_canonical_order() {
            xml.push_str("<Paragraph Type=\"Action\"");
            let centered = matches!(
                entry.field,
                TitleField::Title
                    | TitleField::Credit
                    | TitleField::Author
                    | TitleField::Authors
                    | TitleField::Source
            );
            attribute(
                &mut xml,
                "Alignment",
                if centered { "Center" } else { "Left" },
            )?;
            attribute(&mut xml, "SluglineTitleField", entry.field.key())?;
            let runs = styles::printable_title(&entry.value);
            let canonical = styles::markup(&runs, &mut warnings);
            if !styles::equivalent(&runs, &styles::printable_title(&canonical)) {
                attribute(&mut xml, "SluglineRaw", &entry.value)?;
            }
            // FDX title-page placement is paragraph-based; fields remain standard Text.
            if entry.field == TitleField::Title {
                attribute(&mut xml, "SpaceBefore", "216")?;
            }
            xml.push('>');
            emit_runs(&mut xml, &runs)?;
            xml.push_str("</Paragraph>\n");
        }
        xml.push_str("</Content></TitlePage>\n");
    }
    xml.push_str(ELEMENT_SETTINGS);
    xml.push_str("</FinalDraft>\n");
    Ok(ExportedScript { xml, warnings })
}
