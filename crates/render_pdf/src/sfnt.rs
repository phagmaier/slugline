//! Reading TrueType fonts, and writing subsets of them.
//!
//! Only as much of the format as embedding a `CIDFontType2` needs: the metrics
//! the PDF font descriptor must repeat, a character-to-glyph lookup, and a
//! subsetter that keeps the glyphs a script actually used.
//!
//! ## Why a subsetter rather than the whole file
//!
//! §Phase 7 asks for "font subsetting to keep file size reasonable". Four faces
//! of Courier Prime are 305 KB; a screenplay uses perhaps a hundred and twenty
//! distinct characters of them. Embedding the files whole would make the font
//! the largest thing in almost every export.
//!
//! ## What is trusted, and what is not
//!
//! The input is [`crate::fonts`]' vendored files and nothing else — they are
//! `include_bytes!`d into the binary, so a malformed one is a broken build, not
//! a broken document. Parsing therefore *asserts* rather than degrading, and
//! `every_vendored_face_parses` is the test that runs those assertions.
//! Everything derived from a *user's* script — which characters to keep — is
//! ordinary data and is handled without any such assumption.

use std::collections::{BTreeMap, BTreeSet};

const HEADER: usize = 12;
const RECORD: usize = 16;

/// A parsed face. Borrowed, because every face this crate uses is `'static`
/// bytes compiled into the library.
#[derive(Debug)]
pub(crate) struct Face {
    data: &'static [u8],
    tables: BTreeMap<[u8; 4], (usize, usize)>,
    pub units_per_em: u16,
    pub num_glyphs: u16,
    pub index_to_loc_format: i16,
    pub number_of_h_metrics: u16,
    /// `xMin yMin xMax yMax`, in font units.
    pub bbox: [i16; 4],
    pub ascender: i16,
    pub descender: i16,
    pub cap_height: i16,
    pub italic_angle: f64,
    pub underline_position: i16,
    pub underline_thickness: i16,
    pub weight_class: u16,
}

impl Face {
    pub fn parse(data: &'static [u8]) -> Face {
        assert!(
            data.len() > HEADER,
            "font file is too short to have a header"
        );
        let num_tables = u16(data, 4) as usize;
        let mut tables = BTreeMap::new();
        for index in 0..num_tables {
            let record = HEADER + RECORD * index;
            assert!(
                record + RECORD <= data.len(),
                "table directory runs past the file"
            );
            let mut tag = [0u8; 4];
            tag.copy_from_slice(&data[record..record + 4]);
            let offset = u32(data, record + 8) as usize;
            let length = u32(data, record + 12) as usize;
            assert!(
                offset + length <= data.len(),
                "table {} runs past the file",
                String::from_utf8_lossy(&tag)
            );
            tables.insert(tag, (offset, length));
        }

        let mut face = Face {
            data,
            tables,
            units_per_em: 0,
            num_glyphs: 0,
            index_to_loc_format: 0,
            number_of_h_metrics: 0,
            bbox: [0; 4],
            ascender: 0,
            descender: 0,
            cap_height: 0,
            italic_angle: 0.0,
            underline_position: 0,
            underline_thickness: 0,
            weight_class: 400,
        };

        let head = face.table(b"head");
        face.units_per_em = u16(head, 18);
        face.bbox = [
            i16_at(head, 36),
            i16_at(head, 38),
            i16_at(head, 40),
            i16_at(head, 42),
        ];
        face.index_to_loc_format = i16_at(head, 50);
        assert!(face.units_per_em > 0, "head.unitsPerEm is zero");

        let maxp = face.table(b"maxp");
        face.num_glyphs = u16(maxp, 4);

        let hhea = face.table(b"hhea");
        face.ascender = i16_at(hhea, 4);
        face.descender = i16_at(hhea, 6);
        face.number_of_h_metrics = u16(hhea, 34);

        // `OS/2` and `post` carry what the PDF font descriptor must repeat, and
        // are the two tables a subset written by this crate deliberately leaves
        // out — a `CIDFontType2` needs neither. So they are optional here, which
        // is what lets a test re-parse a subset to check its offsets. The
        // vendored faces have both, and `the_vendored_faces_describe_themselves`
        // is what says so.
        if let Some(os2) = face.optional_table(b"OS/2") {
            face.weight_class = u16(os2, 4);
            // sCapHeight exists from version 2 onwards.
            if u16(os2, 0) >= 2 && os2.len() >= 90 {
                face.cap_height = i16_at(os2, 88);
            }
        }
        if face.cap_height == 0 {
            face.cap_height = face.ascender;
        }
        if let Some(post) = face.optional_table(b"post") {
            // Fixed 16.16, and a small negative angle or zero for these.
            face.italic_angle = f64::from(i32(post, 4)) / 65536.0;
            face.underline_position = i16_at(post, 8);
            face.underline_thickness = i16_at(post, 10);
        }

        face
    }

    fn table(&self, tag: &[u8; 4]) -> &'static [u8] {
        let (offset, length) = self
            .tables
            .get(tag)
            .copied()
            .unwrap_or_else(|| panic!("font has no {} table", String::from_utf8_lossy(tag)));
        &self.data[offset..offset + length]
    }

    fn optional_table(&self, tag: &[u8; 4]) -> Option<&'static [u8]> {
        self.tables
            .get(tag)
            .map(|(offset, length)| &self.data[*offset..*offset + *length])
    }

    /// The glyph a character is drawn with, or 0 — `.notdef` — for one this face
    /// does not have.
    ///
    /// Reads the Windows Unicode BMP subtable (platform 3, encoding 1, format
    /// 4), which is the one every vendored face carries. Characters outside the
    /// BMP have no glyph here and come back as `.notdef`, which is what the page
    /// then shows: an emoji in an action line prints as a box rather than
    /// silently disappearing.
    pub fn glyph_for(&self, character: char) -> u16 {
        let Ok(code) = u16::try_from(u32::from(character)) else {
            return 0;
        };
        let Some(subtable) = self.unicode_subtable() else {
            return 0;
        };
        if u16(subtable, 0) != 4 {
            return 0;
        }
        let segments = usize::from(u16(subtable, 6) / 2);
        let ends = 14;
        let starts = ends + segments * 2 + 2;
        let deltas = starts + segments * 2;
        let ranges = deltas + segments * 2;
        for segment in 0..segments {
            if u16(subtable, ends + segment * 2) < code {
                continue;
            }
            let start = u16(subtable, starts + segment * 2);
            if start > code {
                return 0;
            }
            let delta = u16(subtable, deltas + segment * 2);
            let range_offset = u16(subtable, ranges + segment * 2);
            if range_offset == 0 {
                return code.wrapping_add(delta);
            }
            // The offset is from the idRangeOffset slot itself, in bytes.
            let at =
                ranges + segment * 2 + usize::from(range_offset) + usize::from(code - start) * 2;
            if at + 2 > subtable.len() {
                return 0;
            }
            let glyph = u16(subtable, at);
            return if glyph == 0 {
                0
            } else {
                glyph.wrapping_add(delta)
            };
        }
        0
    }

    fn unicode_subtable(&self) -> Option<&'static [u8]> {
        let cmap = self.optional_table(b"cmap")?;
        let count = usize::from(u16(cmap, 2));
        for index in 0..count {
            let record = 4 + index * 8;
            if u16(cmap, record) == 3 && u16(cmap, record + 2) == 1 {
                let offset = u32(cmap, record + 4) as usize;
                return cmap.get(offset..);
            }
        }
        None
    }

    /// Advance width of a glyph, in font units.
    pub fn advance(&self, glyph: u16) -> u16 {
        let hmtx = self.table(b"hmtx");
        let metrics = usize::from(self.number_of_h_metrics.max(1));
        let index = usize::from(glyph).min(metrics - 1);
        u16(hmtx, index * 4)
    }

    /// The half-open `glyf` range of one glyph. An empty range is a glyph with
    /// no outline, such as the space.
    fn glyph_range(&self, glyph: u16) -> (usize, usize) {
        let loca = self.table(b"loca");
        let index = usize::from(glyph);
        if self.index_to_loc_format == 0 {
            let at = index * 2;
            if at + 4 > loca.len() {
                return (0, 0);
            }
            (
                usize::from(u16(loca, at)) * 2,
                usize::from(u16(loca, at + 2)) * 2,
            )
        } else {
            let at = index * 4;
            if at + 8 > loca.len() {
                return (0, 0);
            }
            (u32(loca, at) as usize, u32(loca, at + 4) as usize)
        }
    }

    fn glyph_data(&self, glyph: u16) -> &'static [u8] {
        let glyf = self.table(b"glyf");
        let (start, end) = self.glyph_range(glyph);
        if start >= end || end > glyf.len() {
            return &[];
        }
        &glyf[start..end]
    }

    /// The glyphs a composite glyph is assembled from. Empty for a simple one.
    fn components(&self, glyph: u16) -> Vec<u16> {
        let data = self.glyph_data(glyph);
        if data.len() < 10 || i16_at(data, 0) >= 0 {
            return Vec::new();
        }
        let mut components = Vec::new();
        let mut at = 10usize;
        loop {
            if at + 4 > data.len() {
                break;
            }
            let flags = u16(data, at);
            components.push(u16(data, at + 2));
            at += 4;
            at += if flags & 0x0001 != 0 { 4 } else { 2 };
            if flags & 0x0008 != 0 {
                at += 2;
            } else if flags & 0x0040 != 0 {
                at += 4;
            } else if flags & 0x0080 != 0 {
                at += 8;
            }
            if flags & 0x0020 == 0 {
                break;
            }
        }
        components
    }

    /// Every glyph that must be kept if `glyphs` are: the closure of `glyphs`
    /// under composition, plus `.notdef`.
    pub fn closure(&self, glyphs: &BTreeSet<u16>) -> BTreeSet<u16> {
        let mut kept = BTreeSet::from([0u16]);
        let mut pending: Vec<u16> = glyphs.iter().copied().collect();
        while let Some(glyph) = pending.pop() {
            if glyph >= self.num_glyphs || !kept.insert(glyph) {
                continue;
            }
            pending.extend(self.components(glyph));
        }
        kept
    }

    /// A font file holding only `kept`, renumbered.
    ///
    /// Returns the file and the old-to-new glyph map. Renumbering is by
    /// ascending old glyph id, so `.notdef` stays 0 and a composite always
    /// refers to a component that is still a valid `uint16`.
    pub fn subset(&self, kept: &BTreeSet<u16>) -> (Vec<u8>, BTreeMap<u16, u16>) {
        let mapping: BTreeMap<u16, u16> = kept
            .iter()
            .enumerate()
            .map(|(new, old)| (*old, new as u16))
            .collect();

        let mut glyf = Vec::new();
        let mut loca = Vec::new();
        let mut hmtx = Vec::new();
        for old in kept {
            loca.extend_from_slice(&(glyf.len() as u32).to_be_bytes());
            let mut data = self.glyph_data(*old).to_vec();
            renumber_components(&mut data, &mapping);
            glyf.extend_from_slice(&data);
            // `loca` entries must be strictly ascending for non-empty glyphs and
            // long-format offsets are unscaled, so any padding is legal; four
            // keeps every glyph word-aligned the way the original file did.
            while glyf.len() % 4 != 0 {
                glyf.push(0);
            }
            hmtx.extend_from_slice(&self.advance(*old).to_be_bytes());
            hmtx.extend_from_slice(&self.left_side_bearing(*old).to_be_bytes());
        }
        loca.extend_from_slice(&(glyf.len() as u32).to_be_bytes());

        let num_glyphs = kept.len() as u16;
        let mut head = self.table(b"head").to_vec();
        // Zeroed before the file checksum is taken; patched once at the end.
        head[8..12].copy_from_slice(&0u32.to_be_bytes());
        head[50..52].copy_from_slice(&1i16.to_be_bytes());
        let mut hhea = self.table(b"hhea").to_vec();
        hhea[34..36].copy_from_slice(&num_glyphs.to_be_bytes());
        let mut maxp = self.table(b"maxp").to_vec();
        maxp[4..6].copy_from_slice(&num_glyphs.to_be_bytes());

        let mut tables: Vec<(&[u8; 4], Vec<u8>)> = vec![
            (b"head", head),
            (b"hhea", hhea),
            (b"maxp", maxp),
            (b"hmtx", hmtx),
            (b"loca", loca),
            (b"glyf", glyf),
        ];
        // The hinting programs. Kept because dropping them is what makes a
        // subset look worse than the font it came from at screen sizes, and they
        // are four kilobytes between them.
        for tag in [b"cvt ", b"fpgm", b"prep"] {
            if let Some(table) = self.optional_table(tag) {
                tables.push((tag, table.to_vec()));
            }
        }
        (build_sfnt(tables), mapping)
    }

    fn left_side_bearing(&self, glyph: u16) -> i16 {
        let hmtx = self.table(b"hmtx");
        let metrics = usize::from(self.number_of_h_metrics.max(1));
        let index = usize::from(glyph);
        let at = if index < metrics {
            index * 4 + 2
        } else {
            metrics * 4 + (index - metrics) * 2
        };
        if at + 2 > hmtx.len() {
            return 0;
        }
        i16_at(hmtx, at)
    }
}

/// Rewrites a composite glyph's component ids into the subset's numbering.
fn renumber_components(data: &mut [u8], mapping: &BTreeMap<u16, u16>) {
    if data.len() < 10 || i16_at(data, 0) >= 0 {
        return;
    }
    let mut at = 10usize;
    loop {
        if at + 4 > data.len() {
            return;
        }
        let flags = u16(data, at);
        let component = u16(data, at + 2);
        // A component outside the closure cannot happen — `closure` put every
        // one of them in — so an absent mapping would be a subsetter bug rather
        // than a font problem, and `.notdef` is the safe thing to draw.
        let new = mapping.get(&component).copied().unwrap_or(0);
        data[at + 2..at + 4].copy_from_slice(&new.to_be_bytes());
        at += 4;
        at += if flags & 0x0001 != 0 { 4 } else { 2 };
        if flags & 0x0008 != 0 {
            at += 2;
        } else if flags & 0x0040 != 0 {
            at += 4;
        } else if flags & 0x0080 != 0 {
            at += 8;
        }
        if flags & 0x0020 == 0 {
            return;
        }
    }
}

/// Assembles a TrueType file from its tables, checksums and all.
fn build_sfnt(mut tables: Vec<(&[u8; 4], Vec<u8>)>) -> Vec<u8> {
    tables.sort_by_key(|(tag, _)| **tag);
    let count = tables.len();
    let entry_selector = (usize::BITS - 1 - count.leading_zeros()) as u16;
    let search_range = (1u16 << entry_selector) * 16;
    let range_shift = (count as u16) * 16 - search_range;

    let mut file = Vec::new();
    file.extend_from_slice(&0x0001_0000u32.to_be_bytes());
    file.extend_from_slice(&(count as u16).to_be_bytes());
    file.extend_from_slice(&search_range.to_be_bytes());
    file.extend_from_slice(&entry_selector.to_be_bytes());
    file.extend_from_slice(&range_shift.to_be_bytes());

    let directory = file.len();
    file.resize(directory + count * RECORD, 0);
    let mut head_at = None;
    for (index, (tag, data)) in tables.iter().enumerate() {
        while file.len() % 4 != 0 {
            file.push(0);
        }
        let offset = file.len();
        if *tag == b"head" {
            head_at = Some(offset);
        }
        let record = directory + index * RECORD;
        file[record..record + 4].copy_from_slice(*tag);
        file[record + 4..record + 8].copy_from_slice(&checksum(data).to_be_bytes());
        file[record + 8..record + 12].copy_from_slice(&(offset as u32).to_be_bytes());
        file[record + 12..record + 16].copy_from_slice(&(data.len() as u32).to_be_bytes());
        file.extend_from_slice(data);
    }
    while file.len() % 4 != 0 {
        file.push(0);
    }

    // head.checkSumAdjustment is the one field defined in terms of the finished
    // file, so it is the last thing written.
    if let Some(head) = head_at {
        let adjustment = 0xB1B0_AFBAu32.wrapping_sub(checksum(&file));
        file[head + 8..head + 12].copy_from_slice(&adjustment.to_be_bytes());
    }
    file
}

fn checksum(data: &[u8]) -> u32 {
    let mut sum = 0u32;
    let mut chunks = data.chunks_exact(4);
    for chunk in &mut chunks {
        sum = sum.wrapping_add(u32::from_be_bytes([chunk[0], chunk[1], chunk[2], chunk[3]]));
    }
    let tail = chunks.remainder();
    if !tail.is_empty() {
        let mut last = [0u8; 4];
        last[..tail.len()].copy_from_slice(tail);
        sum = sum.wrapping_add(u32::from_be_bytes(last));
    }
    sum
}

fn u16(data: &[u8], at: usize) -> u16 {
    u16::from_be_bytes([data[at], data[at + 1]])
}

fn i16_at(data: &[u8], at: usize) -> i16 {
    u16(data, at) as i16
}

fn u32(data: &[u8], at: usize) -> u32 {
    u32::from_be_bytes([data[at], data[at + 1], data[at + 2], data[at + 3]])
}

fn i32(data: &[u8], at: usize) -> i32 {
    u32(data, at) as i32
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::fonts;

    #[test]
    fn every_vendored_face_parses_and_agrees_on_the_grid() {
        for face in fonts::ALL {
            let parsed = Face::parse(face.bytes);
            assert_eq!(parsed.units_per_em, 2048, "{}", face.postscript_name);
            assert!(parsed.num_glyphs > 300, "{}", face.postscript_name);
            // Courier Prime is monospaced, which is the whole reason §5.1 can
            // treat layout as character counting.
            let widths: BTreeSet<u16> = "ABCXYZabcxyz .,'-0189"
                .chars()
                .map(|character| parsed.advance(parsed.glyph_for(character)))
                .collect();
            assert_eq!(
                widths.len(),
                1,
                "{} is not monospaced",
                face.postscript_name
            );
        }
    }

    #[test]
    fn the_vendored_faces_describe_themselves() {
        // The values the PDF font descriptor repeats. If a face were ever
        // replaced by one without an `OS/2` or a `post`, the descriptor would
        // quietly fall back to guesses, and this is what would notice.
        for face in fonts::ALL {
            let parsed = Face::parse(face.bytes);
            let italic = face.postscript_name.contains("Italic");
            let bold = face.postscript_name.contains("Bold");
            assert_eq!(parsed.cap_height, 1187, "{}", face.postscript_name);
            assert!(parsed.underline_thickness > 0, "{}", face.postscript_name);
            assert!(parsed.underline_position < 0, "{}", face.postscript_name);
            assert_eq!(
                parsed.italic_angle != 0.0,
                italic,
                "{}",
                face.postscript_name
            );
            assert_eq!(parsed.weight_class >= 700, bold, "{}", face.postscript_name);
        }
    }

    #[test]
    fn characters_map_to_distinct_glyphs_and_unknown_ones_to_notdef() {
        let face = Face::parse(fonts::REGULAR.bytes);
        assert_ne!(face.glyph_for('A'), 0);
        assert_ne!(face.glyph_for('A'), face.glyph_for('B'));
        assert_ne!(face.glyph_for('é'), 0, "accented Latin is in the font");
        assert_eq!(face.glyph_for('🎬'), 0, "astral planes are not");
        assert_eq!(face.glyph_for('日'), 0);
    }

    #[test]
    fn a_subset_keeps_the_glyphs_asked_for_and_renumbers_from_notdef() {
        let face = Face::parse(fonts::REGULAR.bytes);
        let wanted: BTreeSet<u16> = "INT. HOUSE - DAY"
            .chars()
            .map(|c| face.glyph_for(c))
            .collect();
        let kept = face.closure(&wanted);
        let (subset, mapping) = face.subset(&kept);

        assert_eq!(mapping.get(&0), Some(&0), ".notdef stays glyph zero");
        assert_eq!(mapping.len(), kept.len());
        assert!(
            mapping.values().copied().eq(0..kept.len() as u16),
            "the new ids are 0..n with no gaps"
        );
        assert!(
            subset.len() < fonts::REGULAR.bytes.len() / 4,
            "a sixteen-character subset is far smaller than the face: {} of {}",
            subset.len(),
            fonts::REGULAR.bytes.len()
        );

        // The result is a font file in its own right, and re-parsing it is the
        // strongest cheap check that the tables, offsets and checksums line up.
        let leaked: &'static [u8] = Box::leak(subset.into_boxed_slice());
        let reparsed = Face::parse(leaked);
        assert_eq!(reparsed.num_glyphs, kept.len() as u16);
        assert_eq!(reparsed.units_per_em, face.units_per_em);
        assert_eq!(reparsed.index_to_loc_format, 1);
        for (old, new) in &mapping {
            assert_eq!(
                reparsed.advance(*new),
                face.advance(*old),
                "glyph {old} kept its advance"
            );
        }
    }

    #[test]
    fn an_accented_letter_drags_its_components_into_the_subset() {
        let face = Face::parse(fonts::REGULAR.bytes);
        let accented = face.glyph_for('é');
        let wanted = BTreeSet::from([accented]);
        let kept = face.closure(&wanted);
        assert!(
            kept.len() > 2,
            "é is composed of a base and a mark, so keeping it keeps three glyphs, not two"
        );
        assert!(kept.contains(&face.glyph_for('e')));
    }

    #[test]
    fn subsetting_is_a_pure_function_of_what_was_asked_for() {
        let face = Face::parse(fonts::BOLD.bytes);
        let wanted: BTreeSet<u16> = "FADE IN:".chars().map(|c| face.glyph_for(c)).collect();
        let kept = face.closure(&wanted);
        assert_eq!(face.subset(&kept).0, face.subset(&kept).0);
    }
}
