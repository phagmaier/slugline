//! Offset-stable uppercase display, shared by layout and necessary cue syntax.

fn uppercase_scalar(character: char) -> char {
    let mut mapped = character.to_uppercase();
    match (mapped.next(), mapped.next()) {
        (Some(one), None) if one.len_utf16() == character.len_utf16() => one,
        _ => character,
    }
}

/// Whether ordinary uppercase presentation would change authored spelling.
/// Expanding mappings such as `ß` → `SS` remain authored and need no marker.
pub fn changes_when_uppercased(text: &str) -> bool {
    text.chars()
        .any(|character| uppercase_scalar(character) != character)
}

/// Changes display glyphs only where scalar and UTF-16 boundaries stay exact.
pub fn display_text(text: &str, uppercase: bool) -> String {
    if !uppercase {
        return text.to_owned();
    }
    let mut upper = String::with_capacity(text.len());
    for character in text.chars() {
        upper.push(uppercase_scalar(character));
    }
    upper
}
