//! Just enough PDF to write a screenplay: indirect objects, streams, a
//! cross-reference table, and the two kinds of string the format has.
//!
//! ## Why this is written out rather than taken from a crate
//!
//! §2.6 shortlisted `printpdf`, and ADR 0032 records why it was not taken. The
//! short version is that everything §Phase 7 asks for beyond "put text on a
//! page" is a statement about the *bytes*: a fixed `/ID`, a timestamp that obeys
//! `SOURCE_DATE_EPOCH`, no dependence on hash-map iteration order, and a
//! SHA-256 a golden test can pin. Those are properties of the writer, and this
//! is the writer.
//!
//! Nothing here is compressed. A screenplay is text, the streams are readable in
//! a text editor, `pdftotext` never has to inflate anything, and there is one
//! less place for output to vary. §Phase 7's file-size requirement is answered
//! by subsetting the font, which is where the weight actually was.

use std::fmt::Write as _;

/// A reference to an indirect object. Generation is always zero: nothing here
/// is ever updated in place.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) struct Ref(pub u32);

impl std::fmt::Display for Ref {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(formatter, "{} 0 R", self.0)
    }
}

/// A document under construction.
#[derive(Debug, Default)]
pub(crate) struct Pdf {
    /// Object bodies by number, one-based. `None` is reserved but not yet
    /// written, which is how a page can name its contents before they exist.
    objects: Vec<Option<Vec<u8>>>,
}

impl Pdf {
    pub fn new() -> Pdf {
        Pdf::default()
    }

    /// Takes the next object number without writing anything to it.
    pub fn reserve(&mut self) -> Ref {
        self.objects.push(None);
        Ref(self.objects.len() as u32)
    }

    pub fn put(&mut self, at: Ref, body: impl Into<Vec<u8>>) {
        self.objects[at.0 as usize - 1] = Some(body.into());
    }

    pub fn add(&mut self, body: impl Into<Vec<u8>>) -> Ref {
        let at = self.reserve();
        self.put(at, body);
        at
    }

    /// A stream object: the dictionary entries in `extra`, plus `/Length`.
    pub fn add_stream(&mut self, extra: &str, data: &[u8]) -> Ref {
        let mut body = Vec::new();
        body.extend_from_slice(b"<< /Length ");
        body.extend_from_slice(data.len().to_string().as_bytes());
        if !extra.is_empty() {
            body.push(b' ');
            body.extend_from_slice(extra.as_bytes());
        }
        body.extend_from_slice(b" >>\nstream\n");
        body.extend_from_slice(data);
        body.extend_from_slice(b"\nendstream");
        self.add(body)
    }

    /// Assembles the file. `id` is the document identifier §Phase 7 requires to
    /// be fixed rather than random; both halves of `/ID` are the same, which is
    /// what a file that has never been incrementally updated should say.
    pub fn finish(self, catalog: Ref, info: Ref, id: &[u8; 16]) -> Vec<u8> {
        let mut file = Vec::new();
        file.extend_from_slice(b"%PDF-1.7\n");
        // The conventional high-bit comment: it is what tells a tool copying
        // this file that it is binary, whatever the rest of it looks like.
        file.extend_from_slice(&[b'%', 0xE2, 0xE3, 0xCF, 0xD3, b'\n']);

        let mut offsets = Vec::with_capacity(self.objects.len());
        for (index, body) in self.objects.iter().enumerate() {
            let body = body
                .as_ref()
                .unwrap_or_else(|| panic!("object {} was reserved and never written", index + 1));
            offsets.push(file.len());
            file.extend_from_slice(format!("{} 0 obj\n", index + 1).as_bytes());
            file.extend_from_slice(body);
            file.extend_from_slice(b"\nendobj\n");
        }

        let xref = file.len();
        file.extend_from_slice(format!("xref\n0 {}\n", offsets.len() + 1).as_bytes());
        file.extend_from_slice(b"0000000000 65535 f \n");
        for offset in &offsets {
            file.extend_from_slice(format!("{offset:010} 00000 n \n").as_bytes());
        }

        let id = hex_string(id);
        file.extend_from_slice(
            format!(
                "trailer\n<< /Size {} /Root {catalog} /Info {info} /ID [{id} {id}] >>\n\
                 startxref\n{xref}\n%%EOF\n",
                offsets.len() + 1,
            )
            .as_bytes(),
        );
        file
    }
}

/// A PDF hexadecimal string, `<...>`.
pub(crate) fn hex_string(bytes: &[u8]) -> String {
    let mut out = String::with_capacity(bytes.len() * 2 + 2);
    out.push('<');
    for byte in bytes {
        let _ = write!(out, "{byte:02X}");
    }
    out.push('>');
    out
}

/// A PDF text string, as UTF-16BE with a byte-order mark.
///
/// Not a literal `(...)` string: those are PDFDocEncoding, which has no room for
/// a title with an em dash in it, let alone one in Japanese.
pub(crate) fn text_string(text: &str) -> String {
    let mut bytes = vec![0xFE, 0xFF];
    for unit in text.encode_utf16() {
        bytes.extend_from_slice(&unit.to_be_bytes());
    }
    hex_string(&bytes)
}

/// A PDF name, `/Like This`. Characters outside the safe set are `#`-escaped.
pub(crate) fn name(text: &str) -> String {
    let mut out = String::with_capacity(text.len() + 1);
    out.push('/');
    for byte in text.bytes() {
        if byte.is_ascii_alphanumeric() || matches!(byte, b'-' | b'+' | b'_' | b'.') {
            out.push(byte as char);
        } else {
            let _ = write!(out, "#{byte:02X}");
        }
    }
    out
}

/// A number, with no trailing zeros and no exponent — PDF has no exponents.
pub(crate) fn number(value: f64) -> String {
    // Four decimal places is a ten-thousandth of a point; the grid's smallest
    // real distance is a fifth of one.
    let mut text = format!("{value:.4}");
    if text.contains('.') {
        text.truncate(text.trim_end_matches('0').trim_end_matches('.').len());
    }
    if text == "-0" {
        text = "0".to_owned();
    }
    text
}

/// `D:YYYYMMDDHHmmSS+00'00'`, from Unix seconds, in UTC.
///
/// UTC rather than local time on purpose: a local zone would put the machine
/// that ran the export into the file, and §Phase 7 asks for output that depends
/// on nothing but its input.
pub(crate) fn date_string(epoch_seconds: i64) -> String {
    let days = epoch_seconds.div_euclid(86_400);
    let seconds = epoch_seconds.rem_euclid(86_400);
    let (year, month, day) = civil_from_days(days);
    format!(
        "D:{year:04}{month:02}{day:02}{:02}{:02}{:02}+00'00'",
        seconds / 3600,
        (seconds / 60) % 60,
        seconds % 60,
    )
}

/// Howard Hinnant's `civil_from_days`: the proleptic Gregorian calendar with no
/// table and no library.
fn civil_from_days(days: i64) -> (i64, u32, u32) {
    let shifted = days + 719_468;
    let era = shifted.div_euclid(146_097);
    let day_of_era = shifted.rem_euclid(146_097);
    let year_of_era =
        (day_of_era - day_of_era / 1460 + day_of_era / 36_524 - day_of_era / 146_096) / 365;
    let year = year_of_era + era * 400;
    let day_of_year = day_of_era - (365 * year_of_era + year_of_era / 4 - year_of_era / 100);
    let shifted_month = (5 * day_of_year + 2) / 153;
    let day = (day_of_year - (153 * shifted_month + 2) / 5 + 1) as u32;
    let month = if shifted_month < 10 {
        shifted_month + 3
    } else {
        shifted_month - 9
    } as u32;
    (year + i64::from(month <= 2), month, day)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn numbers_are_written_without_noise() {
        assert_eq!(number(0.0), "0");
        assert_eq!(number(612.0), "612");
        assert_eq!(number(7.2), "7.2");
        assert_eq!(number(841.88976), "841.8898");
        assert_eq!(number(-0.0), "0");
        assert_eq!(number(-1.5), "-1.5");
    }

    #[test]
    fn strings_and_names_are_escaped_rather_than_trusted() {
        assert_eq!(text_string("Hi"), "<FEFF00480069>");
        assert_eq!(text_string("é"), "<FEFF00E9>");
        assert_eq!(name("CourierPrime-Bold"), "/CourierPrime-Bold");
        assert_eq!(name("a b"), "/a#20b");
        assert_eq!(name("a/b"), "/a#2Fb");
    }

    #[test]
    fn dates_are_utc_and_cover_the_awkward_years() {
        assert_eq!(date_string(0), "D:19700101000000+00'00'");
        assert_eq!(date_string(1), "D:19700101000001+00'00'");
        // A leap day, a century that is not a leap year, and one that is.
        assert_eq!(date_string(951_782_400), "D:20000229000000+00'00'");
        assert_eq!(date_string(1_709_164_800), "D:20240229000000+00'00'");
        assert_eq!(date_string(1_753_500_000), "D:20250726032000+00'00'");
        // Before the epoch, which a `SOURCE_DATE_EPOCH` could name.
        assert_eq!(date_string(-1), "D:19691231235959+00'00'");
    }

    #[test]
    fn a_finished_file_has_an_xref_entry_for_every_object() {
        let mut pdf = Pdf::new();
        let info = pdf.add("<< /Title (x) >>");
        let pages = pdf.reserve();
        let catalog = pdf.add(format!("<< /Type /Catalog /Pages {pages} >>"));
        pdf.put(pages, "<< /Type /Pages /Kids [] /Count 0 >>");
        let file = pdf.finish(catalog, info, &[0x2A; 16]);

        let text = String::from_utf8_lossy(&file);
        assert!(text.starts_with("%PDF-1.7\n"));
        assert!(text.ends_with("%%EOF\n"));
        assert!(text.contains("xref\n0 4\n"));
        assert_eq!(text.matches(" 00000 n \n").count(), 3);
        assert!(text.contains(&format!("/Root {catalog}")));
        assert!(text.contains("/ID [<2A2A2A2A2A2A2A2A2A2A2A2A2A2A2A2A> <2A2A"));
    }

    #[test]
    #[should_panic(expected = "was reserved and never written")]
    fn a_reserved_object_that_was_never_written_is_a_bug_rather_than_a_broken_file() {
        let mut pdf = Pdf::new();
        let dangling = pdf.reserve();
        let info = pdf.add("<< >>");
        let _ = pdf.finish(dangling, info, &[0; 16]);
    }
}
