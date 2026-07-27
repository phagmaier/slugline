//! §Phase 7's golden hash test: reference script → PDF → SHA-256 matches a
//! committed value.
//!
//! It is a hash rather than a committed PDF for one reason and one only: a
//! 680 KB binary in the repository would be re-committed on every change to the
//! renderer, and nobody would read the diff. The hash is one line, a change to
//! it is visible, and `sha256sum` on the exported file is how a person checks
//! the claim by hand.
//!
//! **What to do when this fails.** It means the bytes moved, which is either a
//! deliberate change to the renderer or a bug. Look at the PDF before deciding:
//! `cargo run -p slugline_render_pdf --example dump -- <script> /tmp/out.pdf`.
//! Then regenerate with `UPDATE_PDF_HASHES=1 cargo test -p slugline_render_pdf
//! --test golden` and say in the commit message which it was.

use std::collections::BTreeMap;
use std::fs;
use std::path::{Path, PathBuf};

use slugline_document::Document;
use slugline_layout::{paginate, PageConfig};
use slugline_render_pdf::{render, sha256, DocumentInfo};

/// Fixed, so that the hashes describe the renderer rather than the clock.
const EPOCH: i64 = 1_700_000_000;

fn workspace_root() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .parent()
        .and_then(Path::parent)
        .expect("the crate is two levels below the workspace root")
        .to_owned()
}

fn fixtures() -> Vec<PathBuf> {
    let root = workspace_root();
    let mut paths: Vec<PathBuf> = fs::read_dir(root.join("testdata/corpus"))
        .expect("corpus directory")
        .map(|entry| entry.expect("corpus entry").path())
        .filter(|path| path.extension().is_some_and(|it| it == "fountain"))
        .collect();
    paths.push(root.join("testdata/reference-feature.fountain"));
    paths.sort();
    paths
}

fn export(path: &Path, config: &PageConfig) -> Vec<u8> {
    let source = fs::read_to_string(path).expect("UTF-8 Fountain fixture");
    let document = Document::parse(&source);
    let info = DocumentInfo {
        title: document
            .title_page()
            .get(&slugline_document::TitleField::Title)
            .unwrap_or("Untitled")
            .to_owned(),
        author: String::new(),
        created_epoch_seconds: EPOCH,
    };
    render(&paginate(&document, config), config, &info)
}

fn hashes_path() -> PathBuf {
    workspace_root().join("testdata/golden/pdf-hashes.txt")
}

fn committed() -> BTreeMap<String, String> {
    let path = hashes_path();
    let text =
        fs::read_to_string(&path).unwrap_or_else(|error| panic!("{}: {error}", path.display()));
    text.lines()
        .filter(|line| !line.trim_start().starts_with('#') && !line.trim().is_empty())
        .filter_map(|line| {
            let (hash, name) = line.split_once("  ")?;
            Some((name.trim().to_owned(), hash.trim().to_owned()))
        })
        .collect()
}

#[test]
fn every_corpus_file_exports_to_the_committed_bytes() {
    let mut produced: BTreeMap<String, String> = BTreeMap::new();
    for path in fixtures() {
        let stem = path
            .file_stem()
            .and_then(|stem| stem.to_str())
            .expect("UTF-8 fixture stem");
        produced.insert(
            format!("{stem}.pdf"),
            sha256::hex(&export(&path, &PageConfig::us_letter())),
        );
        produced.insert(
            format!("{stem}.a4.pdf"),
            sha256::hex(&export(&path, &PageConfig::a4())),
        );
    }

    if std::env::var_os("UPDATE_PDF_HASHES").is_some() {
        let mut text = String::from(
            "# SHA-256 of every corpus file exported to PDF, at SOURCE_DATE_EPOCH\n\
             # 1700000000. Written by crates/render_pdf/tests/golden.rs; regenerate\n\
             # with UPDATE_PDF_HASHES=1 cargo test -p slugline_render_pdf --test golden.\n\
             # The format is `sha256sum`'s, so a hash here can be checked against an\n\
             # exported file with sha256sum(1).\n",
        );
        for (name, hash) in &produced {
            text.push_str(&format!("{hash}  {name}\n"));
        }
        fs::write(hashes_path(), text).expect("write requested hash update");
    }

    assert_eq!(
        produced,
        committed(),
        "the exported bytes are not the committed ones — see this file's header"
    );
    assert!(produced.len() >= 22, "the whole corpus, on both papers");
}

#[test]
fn exporting_twice_gives_the_same_bytes() {
    // §13's `pdf_output_is_deterministic`, stated as bluntly as it is written:
    // same input, same bytes. Not the same *hash* — the same bytes, so that a
    // difference is visible as a difference rather than as two hex strings.
    let path = workspace_root().join("testdata/reference-feature.fountain");
    let config = PageConfig::us_letter();
    assert_eq!(export(&path, &config), export(&path, &config));
}

#[test]
fn a_different_script_is_a_different_document() {
    // The `/ID` is fixed rather than random (§Phase 7), and "fixed" must not
    // mean "the same for everything": two scripts are two documents and a PDF
    // reader that merged them would be right to treat them as one otherwise.
    let root = workspace_root();
    let one = export(
        &root.join("testdata/corpus/01-minimal.fountain"),
        &PageConfig::us_letter(),
    );
    let two = export(
        &root.join("testdata/corpus/02-every-element.fountain"),
        &PageConfig::us_letter(),
    );
    let id = |bytes: &[u8]| {
        let text = String::from_utf8_lossy(bytes).into_owned();
        let at = text.find("/ID [").expect("every file has an /ID");
        text[at..at + 48].to_owned()
    };
    assert_ne!(id(&one), id(&two));
}
