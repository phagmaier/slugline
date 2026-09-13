//! UTF-16 ↔ UTF-8 offset conversion.
//!
//! Spec §2.4: **the bridge speaks UTF-16 code-unit offsets, always.** Dart
//! strings are UTF-16; Rust strings are UTF-8. This module is the only place in
//! the entire codebase allowed to convert between the two. Every offset field
//! that crosses the bridge is named `*_utf16`, and it is converted here on the
//! way in and on the way out.
//!
//! Conversions are *fallible on purpose*. An offset that lands inside a
//! surrogate pair (Dart) or inside a multi-byte sequence (Rust) is a bug in the
//! caller, and silently rounding it to the nearest boundary would turn that bug
//! into corrupted user text somewhere else, much later. Return `None` and let
//! the caller decide.

/// Length of `s` in UTF-16 code units — i.e. what Dart's `String.length` reports.
pub fn utf16_len(s: &str) -> u32 {
    // ASCII is the common case in screenplays, and for it bytes == code units.
    if s.is_ascii() {
        return clamp_u32(s.len());
    }
    clamp_u32(s.chars().map(char::len_utf16).sum::<usize>())
}

/// Convert a UTF-16 code-unit offset into a UTF-8 byte offset within `s`.
///
/// Returns `None` if the offset is past the end of the string or lands between
/// the two halves of a surrogate pair.
pub fn utf16_to_utf8(s: &str, offset_utf16: u32) -> Option<usize> {
    let target = offset_utf16 as usize;
    // Fast path: ASCII bytes and UTF-16 units coincide, so only bounds matter.
    if s.is_ascii() {
        return (target <= s.len()).then_some(target);
    }
    let mut seen = 0usize;
    for (byte_idx, ch) in s.char_indices() {
        match seen.cmp(&target) {
            std::cmp::Ordering::Equal => return Some(byte_idx),
            // We stepped over the target, so it pointed into a surrogate pair.
            std::cmp::Ordering::Greater => return None,
            std::cmp::Ordering::Less => seen += ch.len_utf16(),
        }
    }
    (seen == target).then_some(s.len())
}

/// Convert a UTF-8 byte offset within `s` into a UTF-16 code-unit offset.
///
/// Returns `None` if the offset is past the end of the string or is not on a
/// `char` boundary.
pub fn utf8_to_utf16(s: &str, offset_utf8: usize) -> Option<u32> {
    if offset_utf8 > s.len() || !s.is_char_boundary(offset_utf8) {
        return None;
    }
    if s.is_ascii() {
        return Some(clamp_u32(offset_utf8));
    }
    Some(utf16_len(&s[..offset_utf8]))
}

/// Convert a UTF-16 range into a byte range. Both ends must be valid, and the
/// range must be non-inverted.
pub fn utf16_range_to_utf8(s: &str, range: std::ops::Range<u32>) -> Option<std::ops::Range<usize>> {
    if range.start > range.end {
        return None;
    }
    let start = utf16_to_utf8(s, range.start)?;
    let end = utf16_to_utf8(s, range.end)?;
    Some(start..end)
}

/// Convert a byte range into a UTF-16 range.
pub fn utf8_range_to_utf16(s: &str, range: std::ops::Range<usize>) -> Option<std::ops::Range<u32>> {
    if range.start > range.end {
        return None;
    }
    let start = utf8_to_utf16(s, range.start)?;
    let end = utf8_to_utf16(s, range.end)?;
    Some(start..end)
}

/// Offsets are `u32` across the bridge (§3.4). A single block long enough to
/// overflow one is not a document we intend to support, but saturating beats
/// wrapping into a small, plausible-looking, catastrophically wrong offset.
fn clamp_u32(value: usize) -> u32 {
    u32::try_from(value).unwrap_or(u32::MAX)
}

#[cfg(test)]
mod tests {
    use super::*;

    /// One character from each width class the conversion has to get right:
    /// ASCII (1 byte / 1 unit), Latin-1 accent (2 / 1), CJK (3 / 1), and an
    /// astral-plane emoji (4 bytes / **2** units — the case that breaks naive code).
    const MIXED: &str = "aé日🎬";

    /// `(byte offset, utf16 offset)` for every character boundary in `MIXED`,
    /// including both ends.
    const BOUNDARIES: &[(usize, u32)] = &[(0, 0), (1, 1), (3, 2), (6, 3), (10, 5)];

    #[test]
    fn utf16_len_counts_code_units_not_chars_or_bytes() {
        assert_eq!(utf16_len(""), 0);
        assert_eq!(utf16_len("abc"), 3);
        assert_eq!(utf16_len("café"), 4);
        assert_eq!(utf16_len("日本"), 2);
        assert_eq!(utf16_len("🎬"), 2, "astral chars are surrogate pairs");
        assert_eq!(utf16_len(MIXED), 5);
        assert_eq!(MIXED.len(), 10, "…while the same string is 10 bytes");
    }

    #[test]
    fn boundaries_convert_in_both_directions() {
        for &(byte, unit) in BOUNDARIES {
            assert_eq!(
                utf16_to_utf8(MIXED, unit),
                Some(byte),
                "utf16 {unit} -> utf8"
            );
            assert_eq!(
                utf8_to_utf16(MIXED, byte),
                Some(unit),
                "utf8 {byte} -> utf16"
            );
        }
    }

    #[test]
    fn offset_inside_a_surrogate_pair_is_rejected() {
        // 4 is the low half of the 🎬 surrogate pair. There is no byte offset
        // that means the same thing, so this must not silently succeed.
        assert_eq!(utf16_to_utf8(MIXED, 4), None);
    }

    #[test]
    fn offset_inside_a_multibyte_sequence_is_rejected() {
        for byte in [2, 4, 5, 7, 8, 9] {
            assert_eq!(
                utf8_to_utf16(MIXED, byte),
                None,
                "byte {byte} is mid-sequence"
            );
        }
    }

    #[test]
    fn past_the_end_is_rejected_in_both_directions() {
        assert_eq!(utf16_to_utf8(MIXED, 6), None);
        assert_eq!(utf16_to_utf8(MIXED, u32::MAX), None);
        assert_eq!(utf8_to_utf16(MIXED, 11), None);
    }

    #[test]
    fn empty_string_accepts_only_offset_zero() {
        assert_eq!(utf16_to_utf8("", 0), Some(0));
        assert_eq!(utf8_to_utf16("", 0), Some(0));
        assert_eq!(utf16_to_utf8("", 1), None);
        assert_eq!(utf8_to_utf16("", 1), None);
    }

    #[test]
    fn round_trip_holds_for_every_boundary_of_a_realistic_line() {
        // A line of dialogue with the awkward characters a real script contains.
        let line = "MARÍA (CONT'D) — 日本語 “quoted” 🎬 …end";
        let mut byte = 0usize;
        while byte <= line.len() {
            if line.is_char_boundary(byte) {
                let unit = utf8_to_utf16(line, byte).expect("boundary converts");
                assert_eq!(utf16_to_utf8(line, unit), Some(byte));
            }
            byte += 1;
        }
    }

    #[test]
    // Inverted ranges are exactly what this test is about: a buggy caller can
    // hand us one, and we must reject it rather than panic on the slice.
    #[allow(clippy::reversed_empty_ranges)]
    fn ranges_convert_and_reject_inversions() {
        assert_eq!(utf16_range_to_utf8(MIXED, 1..3), Some(1..6));
        assert_eq!(utf8_range_to_utf16(MIXED, 1..6), Some(1..3));
        assert_eq!(utf16_range_to_utf8(MIXED, 3..1), None);
        assert_eq!(utf8_range_to_utf16(MIXED, 6..1), None);
        // An inverted range must be rejected even when both ends are valid.
        assert_eq!(utf16_range_to_utf8(MIXED, 5..0), None);
    }

    #[test]
    fn slicing_with_a_converted_range_yields_the_expected_text() {
        let text = "INT. CAFÉ — 日 🎬";
        let range = utf16_range_to_utf8(text, 5..9).expect("valid range");
        assert_eq!(&text[range], "CAFÉ");
    }
}
