//! Renders a Fountain file to a PDF, for looking at.
//!
//! `cargo run -p slugline_render_pdf --example dump -- script.fountain out.pdf`
//! Not part of the application; the export path is the bridge's.

use slugline_document::Document;
use slugline_layout::{paginate, PageConfig};
use slugline_render_pdf::{render, DocumentInfo};

fn main() {
    let mut args = std::env::args().skip(1);
    let (source, out) = (args.next().expect("input"), args.next().expect("output"));
    let config = match args.next().as_deref() {
        Some("a4") => PageConfig::a4(),
        _ => PageConfig::us_letter(),
    };
    let text = std::fs::read_to_string(&source).expect("readable Fountain");
    let bytes = render(
        &paginate(&Document::parse(&text), &config),
        &config,
        &DocumentInfo {
            title: "Dump".into(),
            author: "Nobody".into(),
            created_epoch_seconds: 1_700_000_000,
        },
    );
    std::fs::write(out, bytes).expect("writable output");
}
