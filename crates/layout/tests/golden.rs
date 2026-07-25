use std::fs;
use std::path::{Path, PathBuf};

use slugline_document::Document;
use slugline_layout::{paginate, PageConfig};

fn workspace_root() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .parent()
        .and_then(Path::parent)
        .expect("layout crate is two levels below the workspace root")
        .to_owned()
}

fn fixtures() -> Vec<PathBuf> {
    let root = workspace_root();
    let mut paths: Vec<_> = fs::read_dir(root.join("testdata/corpus"))
        .expect("corpus directory")
        .map(|entry| entry.expect("corpus entry").path())
        .filter(|path| {
            path.extension()
                .is_some_and(|extension| extension == "fountain")
        })
        .collect();
    paths.push(root.join("testdata/reference-feature.fountain"));
    paths.sort();
    paths
}

fn assert_golden(source_path: &Path, config: &PageConfig, suffix: &str) {
    let source = fs::read_to_string(source_path).expect("UTF-8 Fountain fixture");
    let dump = paginate(&Document::parse(&source), config).debug_dump();
    let stem = source_path
        .file_stem()
        .and_then(|stem| stem.to_str())
        .expect("UTF-8 fixture stem");
    let golden_path = workspace_root()
        .join("testdata/golden")
        .join(format!("{stem}{suffix}.layout.txt"));

    if std::env::var_os("UPDATE_LAYOUT_GOLDENS").is_some() {
        fs::write(&golden_path, &dump).expect("write requested golden update");
    }
    let expected = fs::read_to_string(&golden_path)
        .unwrap_or_else(|error| panic!("{}: {error}", golden_path.display()));
    assert_eq!(dump, expected, "{}", source_path.display());
}

#[test]
fn every_corpus_file_has_a_stable_letter_layout() {
    let fixtures = fixtures();
    assert!(fixtures.len() >= 11, "the complete corpus must be covered");
    for path in fixtures {
        assert_golden(&path, &PageConfig::us_letter(), "");
    }
}

#[test]
fn a4_line_count_has_a_golden_layout() {
    let source = workspace_root().join("testdata/corpus/01-minimal.fountain");
    assert_golden(&source, &PageConfig::a4(), ".a4");
}
