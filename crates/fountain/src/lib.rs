//! Fountain parsing and serialisation.
//!
//! Layering rule (§2.5): this crate depends on nothing else in the workspace and
//! performs no I/O. It is a pure function from bytes to a syntax tree and back.
//!
//! ```
//! use slugline_fountain::{parse, serialise, BlockKind, Output};
//!
//! let source = "INT. HOUSE - DAY\n\nJOHN\nHello.\n";
//! let script = parse(source);
//! assert_eq!(script.elements[0].kind, BlockKind::SceneHeading);
//!
//! let elements: Vec<_> = script.elements.iter().map(|e| e.as_ref()).collect();
//! let written = serialise(&Output {
//!     title_page: &script.title_page,
//!     elements: &elements,
//!     source: Some(source),
//!     bom: script.bom,
//!     line_ending: script.line_ending,
//! });
//! assert_eq!(written, source);
//! ```
//!
//! Two properties hold for every input, and both are load-bearing for §1.2's
//! rule that losing user text is a P0 defect:
//!
//! 1. [`parse`] is total. There is no error type, no panic, and no input it
//!    rejects — an unreadable file still opens, as Action and Opaque blocks.
//! 2. Parsing and re-serialising a document nobody has edited returns the
//!    original bytes exactly, including line endings, trailing whitespace and a
//!    UTF-8 BOM. See [`parse`] for the provenance invariant that makes this so.

pub mod case;
pub mod emphasis;
mod infer;
mod lines;
mod model;
pub mod omission;
mod parse;
mod serialise;
mod syntax;

pub use emphasis::{Emphasis, EmphasisRun};
pub use infer::{infer_kind, Context};
pub use lines::detect_line_ending;
pub use model::{
    BlockKind, Element, ElementRef, LineEnding, Script, TitleEntry, TitleField, TitlePage,
};
pub use parse::parse;
pub use serialise::{needs_blank_between, serialise, Output};
pub use syntax::{dialogue_lyric_marker_utf8, split_scene_number, without_notes_and_boneyards};

/// Name of the format this crate reads and writes.
pub const FORMAT_NAME: &str = "fountain";

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn crate_is_wired_into_the_workspace() {
        assert_eq!(FORMAT_NAME, "fountain");
    }
}
