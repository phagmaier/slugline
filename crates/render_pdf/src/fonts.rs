//! The vendored typeface.
//!
//! §Phase 7: "Courier Prime vendored and embedded, with the OFL licence file
//! shipped in the bundle". The four faces and `OFL.txt` are in `fonts/` beside
//! this crate, taken unmodified from the upstream release, and they are
//! `include_bytes!`d rather than read at run time — §1.2 rules out font
//! downloads, and a screenplay that renders differently because a system font
//! moved would not be a screenplay you could send anyone.
//!
//! `OFL.txt` is included here as well as shipped, so that the licence cannot be
//! dropped from a package without also breaking the build.

/// One face, with the PostScript name a PDF font dictionary must give it.
#[derive(Debug, Clone, Copy)]
pub(crate) struct VendoredFace {
    pub postscript_name: &'static str,
    pub bytes: &'static [u8],
}

pub(crate) const REGULAR: VendoredFace = VendoredFace {
    postscript_name: "CourierPrime",
    bytes: include_bytes!("../fonts/CourierPrime-Regular.ttf"),
};

pub(crate) const BOLD: VendoredFace = VendoredFace {
    postscript_name: "CourierPrime-Bold",
    bytes: include_bytes!("../fonts/CourierPrime-Bold.ttf"),
};

pub(crate) const ITALIC: VendoredFace = VendoredFace {
    postscript_name: "CourierPrime-Italic",
    bytes: include_bytes!("../fonts/CourierPrime-Italic.ttf"),
};

pub(crate) const BOLD_ITALIC: VendoredFace = VendoredFace {
    postscript_name: "CourierPrime-BoldItalic",
    bytes: include_bytes!("../fonts/CourierPrime-BoldItalic.ttf"),
};

#[cfg(test)]
pub(crate) const ALL: &[VendoredFace] = &[REGULAR, BOLD, ITALIC, BOLD_ITALIC];

/// The licence the faces are under, embedded so that it ships with them.
pub const OPEN_FONT_LICENCE: &str = include_str!("../fonts/OFL.txt");

/// Which of the four a run of text is drawn in.
///
/// Underline is not a face — there is no underlined Courier Prime — so it is
/// drawn as a rule under the text and does not appear here.
#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord, Hash)]
pub(crate) enum Style {
    Regular,
    Bold,
    Italic,
    BoldItalic,
}

impl Style {
    #[cfg(test)]
    pub const ALL: [Style; 4] = [
        Style::Regular,
        Style::Bold,
        Style::Italic,
        Style::BoldItalic,
    ];

    pub const fn of(bold: bool, italic: bool) -> Style {
        match (bold, italic) {
            (false, false) => Style::Regular,
            (true, false) => Style::Bold,
            (false, true) => Style::Italic,
            (true, true) => Style::BoldItalic,
        }
    }

    pub const fn face(self) -> VendoredFace {
        match self {
            Style::Regular => REGULAR,
            Style::Bold => BOLD,
            Style::Italic => ITALIC,
            Style::BoldItalic => BOLD_ITALIC,
        }
    }

    /// The PDF resource name this face is reached by on a page.
    pub const fn resource(self) -> &'static str {
        match self {
            Style::Regular => "F1",
            Style::Bold => "F2",
            Style::Italic => "F3",
            Style::BoldItalic => "F4",
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn the_licence_ships_with_the_faces() {
        assert!(OPEN_FONT_LICENCE.contains("SIL OPEN FONT LICENSE Version 1.1"));
        assert!(OPEN_FONT_LICENCE.contains("Courier Prime"));
    }

    #[test]
    fn every_style_has_its_own_face_and_resource_name() {
        let names: Vec<&str> = Style::ALL
            .iter()
            .map(|s| s.face().postscript_name)
            .collect();
        assert_eq!(
            names,
            [
                "CourierPrime",
                "CourierPrime-Bold",
                "CourierPrime-Italic",
                "CourierPrime-BoldItalic"
            ]
        );
        let resources: Vec<&str> = Style::ALL.iter().map(|s| s.resource()).collect();
        assert_eq!(resources, ["F1", "F2", "F3", "F4"]);
        assert_eq!(Style::of(true, true), Style::BoldItalic);
        assert_eq!(Style::of(false, false), Style::Regular);
    }
}
