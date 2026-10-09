//! Lossless semantic records inside real Fountain boneyards (ADR 0061).
//!
//! Fountain has no standalone Dialogue marker. A commented source fragment alone
//! therefore cannot remember a partial dialogue's kind after its cue is edited.
//! These readable records retain model text and semantics, never document ids.

use std::fmt::Write;

use crate::{BlockKind, Element};

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Omission {
    pub elements: Vec<Element>,
    pub left: Option<Element>,
    pub right: Option<Element>,
    pub before: Option<Element>,
    pub following: Vec<Element>,
    pub after: Option<Element>,
    pub preceding: Vec<Element>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct InvalidOmission;

/// The visible remainder must have the same kind before and after a save.
/// The record retains its original kind for restoration; the ordinary grammar
/// determines what can still be printed outside the interrupted speech.
pub fn visible_remainder_kind(element: &Element, after_boneyard: bool) -> BlockKind {
    if after_boneyard && element.kind.continues_dialogue() {
        BlockKind::Action
    } else if matches!(element.kind, BlockKind::Dialogue | BlockKind::Parenthetical) {
        crate::infer_kind(
            &element.text,
            crate::Context {
                previous: Some(BlockKind::Character),
                current: element.kind,
                next: None,
            },
        )
        .unwrap_or(element.kind)
    } else {
        element.kind
    }
}

/// A necessary orphan cue marker also preserves its authored rendering case.
/// Kind/forcing changes here belong to the omission gesture, never Save.
pub fn visible_remainder_forced(element: &Element, after_boneyard: bool) -> bool {
    visible_remainder_kind(element, after_boneyard) != element.kind
        || (element.kind == BlockKind::Character
            && crate::case::changes_when_uppercased(&element.text))
        || element.forced
}

/// Escaping every slash makes even unmatched/nested comment delimiters safe.
pub fn encode_omission(omission: &Omission) -> String {
    let mut out = String::from("/*\nSlugline omission v2\n");
    for (label, boundary) in [
        ("left", &omission.left),
        ("right", &omission.right),
        ("before", &omission.before),
        ("after-seam", &omission.after),
    ] {
        match boundary {
            Some(element) => write_element(&mut out, label, element),
            None => {
                out.push_str(label);
                out.push_str(" none\n");
            }
        }
    }
    writeln!(out, "preceding {}", omission.preceding.len()).expect("String writes do not fail");
    for element in &omission.preceding {
        write_element(&mut out, "prior", element);
    }
    writeln!(out, "following {}", omission.following.len()).expect("String writes do not fail");
    for element in &omission.following {
        write_element(&mut out, "after", element);
    }
    for element in &omission.elements {
        write_element(&mut out, "block", element);
    }
    let checksum = record_checksum(out.as_bytes());
    writeln!(out, "checksum {checksum:016x}").expect("String writes do not fail");
    out.push_str("*/");
    out
}

// Detect accidental damage before any semantic fragments are consumed. This
// is an integrity check, not authentication of externally authored records.
fn record_checksum(bytes: &[u8]) -> u64 {
    bytes.iter().fold(0xcbf29ce484222325u64, |hash, byte| {
        (hash ^ u64::from(*byte)).wrapping_mul(0x100000001b3)
    })
}

fn write_element(out: &mut String, label: &str, element: &Element) {
    out.push_str(label);
    out.push(' ');
    out.push_str(kind_name(element.kind));
    if let BlockKind::Section { level } = element.kind {
        write!(out, "-{level}").expect("String writes do not fail");
    }
    out.push(' ');
    out.push(if element.forced { '1' } else { '0' });
    out.push(' ');
    out.push(if element.dual { '1' } else { '0' });
    out.push_str(" \"");
    for c in element.text.chars() {
        match c {
            '\\' => out.push_str("\\\\"),
            '/' => out.push_str("\\x2f"),
            '[' => out.push_str("\\x5b"),
            ']' => out.push_str("\\x5d"),
            '"' => out.push_str("\\\""),
            '\n' => out.push_str("\\n"),
            '\r' => out.push_str("\\r"),
            _ => out.push(c),
        }
    }
    out.push_str("\"\n");
}

fn kind_name(kind: BlockKind) -> &'static str {
    match kind {
        BlockKind::SceneHeading => "scene",
        BlockKind::Action => "action",
        BlockKind::Character => "character",
        BlockKind::Dialogue => "dialogue",
        BlockKind::Parenthetical => "parenthetical",
        BlockKind::Transition => "transition",
        BlockKind::Centered => "centered",
        BlockKind::Lyric => "lyric",
        BlockKind::Section { .. } => "section",
        BlockKind::Synopsis => "synopsis",
        BlockKind::Note => "note",
        BlockKind::PageBreak => "page-break",
        BlockKind::Opaque => "boneyard",
    }
}

fn parse_kind(name: &str) -> Option<BlockKind> {
    Some(match name {
        "scene" => BlockKind::SceneHeading,
        "action" => BlockKind::Action,
        "character" => BlockKind::Character,
        "dialogue" => BlockKind::Dialogue,
        "parenthetical" => BlockKind::Parenthetical,
        "transition" => BlockKind::Transition,
        "centered" => BlockKind::Centered,
        "lyric" => BlockKind::Lyric,
        "synopsis" => BlockKind::Synopsis,
        "note" => BlockKind::Note,
        "page-break" => BlockKind::PageBreak,
        "boneyard" => BlockKind::Opaque,
        name => {
            let level = name.strip_prefix("section-")?.parse().ok()?;
            if !(1..=6).contains(&level) {
                return None;
            }
            BlockKind::Section { level }
        }
    })
}

/// None means a foreign comment; a recognizable malformed record is an error.
pub fn decode_omission(text: &str) -> Result<Option<Omission>, InvalidOmission> {
    let trimmed = text.trim();
    let Some(rest) = trimmed.strip_prefix("/*") else {
        return Ok(None);
    };
    if !rest.trim_start().starts_with("Slugline omission") {
        // A damaged header does not turn a witnessed record into foreign
        // printable source. Recognize its remaining record structure as well.
        if ["\nleft ", "\nright ", "\nblock ", "\nchecksum "]
            .iter()
            .all(|label| rest.contains(label))
        {
            return Err(InvalidOmission);
        }
        return Ok(None);
    }
    let body = rest.strip_suffix("*/").ok_or(InvalidOmission)?;
    let checksum_start = body.rfind("checksum ").ok_or(InvalidOmission)?;
    let checksum_line = &body[checksum_start..];
    let expected = checksum_line
        .strip_prefix("checksum ")
        .and_then(|value| value.strip_suffix('\n'))
        .filter(|value| value.len() == 16)
        .and_then(|value| u64::from_str_radix(value, 16).ok())
        .ok_or(InvalidOmission)?;
    let payload_end = 2 + checksum_start;
    if record_checksum(&trimmed.as_bytes()[..payload_end]) != expected {
        return Err(InvalidOmission);
    }
    let mut lines = body[..checksum_start].lines();
    if lines.next() != Some("") || lines.next() != Some("Slugline omission v2") {
        return Err(InvalidOmission);
    }
    let left = parse_boundary(lines.next().ok_or(InvalidOmission)?, "left")?;
    let right = parse_boundary(lines.next().ok_or(InvalidOmission)?, "right")?;
    let before = parse_boundary(lines.next().ok_or(InvalidOmission)?, "before")?;
    let after = parse_boundary(lines.next().ok_or(InvalidOmission)?, "after-seam")?;
    let count = lines
        .next()
        .and_then(|line| line.strip_prefix("preceding "))
        .and_then(|count| count.parse::<usize>().ok())
        .ok_or(InvalidOmission)?;
    let mut preceding = Vec::new();
    for _ in 0..count {
        let line = lines
            .next()
            .and_then(|line| line.strip_prefix("prior "))
            .ok_or(InvalidOmission)?;
        preceding.push(parse_element(line)?);
    }
    let count = lines
        .next()
        .and_then(|line| line.strip_prefix("following "))
        .and_then(|count| count.parse::<usize>().ok())
        .ok_or(InvalidOmission)?;
    let mut following = Vec::new();
    for _ in 0..count {
        let line = lines
            .next()
            .and_then(|line| line.strip_prefix("after "))
            .ok_or(InvalidOmission)?;
        following.push(parse_element(line)?);
    }
    let elements = lines
        .map(|line| parse_element(line.strip_prefix("block ").ok_or(InvalidOmission)?))
        .collect::<Result<Vec<_>, _>>()?;
    if elements.is_empty() {
        return Err(InvalidOmission);
    }
    Ok(Some(Omission {
        elements,
        left,
        right,
        before,
        following,
        after,
        preceding,
    }))
}

fn parse_boundary(line: &str, label: &str) -> Result<Option<Element>, InvalidOmission> {
    let rest = line
        .strip_prefix(label)
        .and_then(|s| s.strip_prefix(' '))
        .ok_or(InvalidOmission)?;
    if rest == "none" {
        Ok(None)
    } else {
        parse_element(rest).map(Some)
    }
}

fn parse_element(line: &str) -> Result<Element, InvalidOmission> {
    let mut fields = line.splitn(4, ' ');
    let kind = parse_kind(fields.next().ok_or(InvalidOmission)?).ok_or(InvalidOmission)?;
    let flag = |value| match value {
        Some("0") => Ok(false),
        Some("1") => Ok(true),
        _ => Err(InvalidOmission),
    };
    let forced = flag(fields.next())?;
    let dual = flag(fields.next())?;
    let quoted = fields.next().ok_or(InvalidOmission)?;
    let escaped = quoted
        .strip_prefix('"')
        .and_then(|s| s.strip_suffix('"'))
        .ok_or(InvalidOmission)?;
    let mut text = String::with_capacity(escaped.len());
    let mut chars = escaped.chars();
    while let Some(c) = chars.next() {
        match c {
            '\\' => text.push(match chars.next() {
                Some('\\') => '\\',
                Some('x') => match (chars.next(), chars.next()) {
                    (Some('2'), Some('f')) => '/',
                    (Some('5'), Some('b')) => '[',
                    (Some('5'), Some('d')) => ']',
                    _ => return Err(InvalidOmission),
                },
                Some('"') => '"',
                Some('n') => '\n',
                Some('r') => '\r',
                _ => return Err(InvalidOmission),
            }),
            '/' | '"' => return Err(InvalidOmission),
            c => text.push(c),
        }
    }
    Ok(Element {
        kind,
        text,
        forced,
        dual,
        provenance: None,
    })
}

/// Removes only the outer comment delimiters. Unclosed foreign boneyards run to
/// EOF; trailing source after a closed comment is retained, never discarded.
pub fn restore_boneyard_source(text: &str) -> Option<String> {
    let text = text.trim_start();
    let body = text.strip_prefix("/*")?;
    let spans = crate::syntax::matched_spans(text.as_bytes(), b"/*", b"*/");
    match spans.iter().find(|span| span.start == 0) {
        Some(span) => {
            let mut source = body[..span.end - 4].to_owned();
            source.push_str(&text[span.end..]);
            Some(source)
        }
        None => Some(body.to_owned()),
    }
}

/// Whether the outer boneyard closes, including nested comments.
pub fn boneyard_is_closed(text: &str) -> bool {
    let text = text.trim_start();
    crate::syntax::matched_spans(text.as_bytes(), b"/*", b"*/")
        .iter()
        .any(|span| span.start == 0)
}

/// A fractured protected opener must not capture the generated omission.
/// Notes also need balanced internal delimiters before their outer wrapping.
pub fn omission_boundary_is_safe(kind: BlockKind, text: &str) -> bool {
    if kind == BlockKind::Note {
        return crate::syntax::note_text_is_balanced(text);
    }
    if !crate::syntax::note_openers_are_closed(text) {
        return false;
    }
    let bytes = text.as_bytes();
    let mut depth = 0usize;
    let mut index = 0;
    while index + 1 < bytes.len() {
        if &bytes[index..index + 2] == b"/*" {
            depth += 1;
            index += 2;
        } else if &bytes[index..index + 2] == b"*/" {
            depth = depth.saturating_sub(1);
            index += 2;
        } else {
            index += 1;
        }
    }
    depth == 0
}
