//! The syntax types the parser produces and the serialiser consumes.
//!
//! These live here rather than in `document` because of the layering rule
//! (§2.5): `document` may depend on `fountain`, never the reverse. `document`
//! wraps [`Element`] in a [`crate::Element`]-shaped `Block` that adds a
//! `BlockId`, and reuses [`BlockKind`] and [`TitlePage`] verbatim.

use std::ops::Range;

/// The element types the editor models (§3.1).
///
/// Anything the parser recognises but the editor does not model — a boneyard
/// comment, for instance — becomes [`BlockKind::Opaque`] and round-trips
/// verbatim rather than gaining a variant here.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum BlockKind {
    SceneHeading,
    Action,
    Character,
    Dialogue,
    Parenthetical,
    Transition,
    Centered,
    Lyric,
    Section {
        level: u8,
    },
    Synopsis,
    Note,
    PageBreak,
    /// Valid Fountain the editor does not model. Round-trips verbatim.
    Opaque,
}

impl BlockKind {
    /// Whether consecutive source lines merge into one block of this kind.
    ///
    /// Everything else is a single line by construction: a scene heading is one
    /// line, a section is one line, and a second line following either of them
    /// starts an Action.
    pub fn is_multiline(self) -> bool {
        matches!(
            self,
            BlockKind::Action | BlockKind::Dialogue | BlockKind::Note | BlockKind::Opaque
        )
    }

    /// Whether a block of this kind can be followed, with no blank line
    /// between, by dialogue or a parenthetical.
    pub fn opens_dialogue(self) -> bool {
        matches!(
            self,
            BlockKind::Character | BlockKind::Parenthetical | BlockKind::Dialogue
        )
    }

    /// Whether a block of this kind may follow a dialogue-context block with no
    /// blank line between them.
    pub fn continues_dialogue(self) -> bool {
        matches!(self, BlockKind::Dialogue | BlockKind::Parenthetical)
    }
}

/// The line terminator a document uses.
///
/// Retained so that re-serialising an edited block does not silently convert a
/// CRLF file into a mixed-ending one.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub enum LineEnding {
    #[default]
    Lf,
    CrLf,
}

impl LineEnding {
    pub fn as_str(self) -> &'static str {
        match self {
            LineEnding::Lf => "\n",
            LineEnding::CrLf => "\r\n",
        }
    }
}

/// A title-page key.
///
/// Unknown keys are preserved exactly as written in [`TitleField::Other`]; the
/// title page is user data, and a key we do not recognise is still theirs.
#[derive(Debug, Clone, PartialEq, Eq, Hash)]
pub enum TitleField {
    Title,
    Credit,
    Author,
    Authors,
    Source,
    DraftDate,
    Contact,
    Copyright,
    Notes,
    Other(String),
}

impl TitleField {
    /// Matches a key case-insensitively, ignoring surrounding whitespace.
    pub fn from_key(key: &str) -> TitleField {
        match key.trim().to_ascii_lowercase().as_str() {
            "title" => TitleField::Title,
            "credit" => TitleField::Credit,
            "author" => TitleField::Author,
            "authors" => TitleField::Authors,
            "source" => TitleField::Source,
            "draft date" => TitleField::DraftDate,
            "contact" => TitleField::Contact,
            "copyright" => TitleField::Copyright,
            "notes" => TitleField::Notes,
            _ => TitleField::Other(key.trim().to_string()),
        }
    }

    /// The spelling used when the title page is re-serialised.
    pub fn key(&self) -> &str {
        match self {
            TitleField::Title => "Title",
            TitleField::Credit => "Credit",
            TitleField::Author => "Author",
            TitleField::Authors => "Authors",
            TitleField::Source => "Source",
            TitleField::DraftDate => "Draft date",
            TitleField::Contact => "Contact",
            TitleField::Copyright => "Copyright",
            TitleField::Notes => "Notes",
            TitleField::Other(key) => key,
        }
    }

    /// Position in the canonical emission order. Unknown keys sort last, in the
    /// order the user wrote them.
    fn rank(&self) -> u8 {
        match self {
            TitleField::Title => 0,
            TitleField::Credit => 1,
            TitleField::Author => 2,
            TitleField::Authors => 3,
            TitleField::Source => 4,
            TitleField::DraftDate => 5,
            TitleField::Contact => 6,
            TitleField::Copyright => 7,
            TitleField::Notes => 8,
            TitleField::Other(_) => 9,
        }
    }
}

/// One `Key: value` pair. `value` holds multi-line values with `\n` between
/// lines, whatever the file's line ending is.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct TitleEntry {
    pub field: TitleField,
    pub value: String,
}

/// The title page, in the order the file wrote it.
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct TitlePage {
    pub entries: Vec<TitleEntry>,
    /// Byte range in the original source this title page was parsed from,
    /// including the blank lines that terminate it. `None` once edited.
    pub provenance: Option<Range<usize>>,
}

impl TitlePage {
    pub fn is_empty(&self) -> bool {
        self.entries.is_empty()
    }

    pub fn get(&self, field: &TitleField) -> Option<&str> {
        self.entries
            .iter()
            .find(|e| &e.field == field)
            .map(|e| e.value.as_str())
    }

    /// Sets a field, replacing the first entry with that key or appending a new
    /// one. An empty value removes the entry.
    pub fn set(&mut self, field: TitleField, value: String) {
        self.provenance = None;
        match self.entries.iter_mut().find(|e| e.field == field) {
            Some(entry) if value.is_empty() => {
                let field = entry.field.clone();
                self.entries.retain(|e| e.field != field);
            }
            Some(entry) => entry.value = value,
            None if value.is_empty() => {}
            None => self.entries.push(TitleEntry { field, value }),
        }
    }

    /// The entries in canonical emission order (§ Phase 1, "Title page emitted
    /// in canonical order"). Stable: equal ranks keep their written order.
    pub fn in_canonical_order(&self) -> Vec<&TitleEntry> {
        let mut entries: Vec<&TitleEntry> = self.entries.iter().collect();
        entries.sort_by_key(|e| e.field.rank());
        entries
    }
}

/// A parsed element, before `document` gives it an identity.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Element {
    pub kind: BlockKind,
    /// User-visible text with emphasis markup retained inline, but with the
    /// element marker (`.`, `@`, `>`, `!`, `~`, `#`, `=`) removed — the marker
    /// is carried by `kind` and `forced`, and is re-added on serialisation.
    pub text: String,
    /// The element type was pinned by explicit Fountain syntax (§3.1).
    pub forced: bool,
    /// Dual-dialogue right column marker (Fountain `^`).
    pub dual: bool,
    /// Byte range in the source this element was parsed from, including the
    /// blank lines that follow it.
    pub provenance: Option<Range<usize>>,
}

impl Element {
    pub fn as_ref(&self) -> ElementRef<'_> {
        ElementRef {
            kind: self.kind,
            text: &self.text,
            forced: self.forced,
            dual: self.dual,
            provenance: self.provenance.clone(),
        }
    }
}

/// A borrowed view of an element, so `document` can serialise its own blocks
/// without copying their text.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ElementRef<'a> {
    pub kind: BlockKind,
    pub text: &'a str,
    pub forced: bool,
    pub dual: bool,
    pub provenance: Option<Range<usize>>,
}

/// A parsed Fountain file.
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct Script {
    pub title_page: TitlePage,
    pub elements: Vec<Element>,
    /// The source began with a UTF-8 BOM, which is re-emitted on save.
    pub bom: bool,
    pub line_ending: LineEnding,
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn unknown_title_keys_keep_their_spelling() {
        let field = TitleField::from_key("  Revision Colour  ");
        assert_eq!(field, TitleField::Other("Revision Colour".to_string()));
        assert_eq!(field.key(), "Revision Colour");
    }

    #[test]
    fn known_title_keys_are_case_insensitive() {
        assert_eq!(TitleField::from_key("DRAFT DATE"), TitleField::DraftDate);
        assert_eq!(TitleField::from_key("title"), TitleField::Title);
    }

    #[test]
    fn canonical_order_puts_title_first_and_unknown_keys_last() {
        let page = TitlePage {
            entries: vec![
                TitleEntry {
                    field: TitleField::Other("Zebra".into()),
                    value: "z".into(),
                },
                TitleEntry {
                    field: TitleField::Contact,
                    value: "c".into(),
                },
                TitleEntry {
                    field: TitleField::Title,
                    value: "t".into(),
                },
            ],
            provenance: None,
        };
        let keys: Vec<&str> = page
            .in_canonical_order()
            .iter()
            .map(|e| e.field.key())
            .collect();
        assert_eq!(keys, ["Title", "Contact", "Zebra"]);
    }

    #[test]
    fn setting_an_empty_value_removes_the_entry() {
        let mut page = TitlePage::default();
        page.set(TitleField::Title, "Big Fish".into());
        assert_eq!(page.get(&TitleField::Title), Some("Big Fish"));
        page.set(TitleField::Title, String::new());
        assert!(page.is_empty());
    }
}
