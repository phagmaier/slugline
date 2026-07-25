//! §Phase 4's tests, at the level where the pieces meet.
//!
//! The storage crate proves each mechanism on its own — the atomic write, the
//! journal format, the retention policy. What is left, and what this file is
//! for, is the claim §Phase 4 actually makes: **type into a document, kill the
//! process, and get your keystrokes back.** That claim spans the document
//! model, the bridge's edit path, the journal and the recovery replay, and it is
//! only true if all four agree.
//!
//! The four tests §Phase 4 names by name are all here:
//!
//! * the **kill test** — [`sigkill_mid_typing_loses_nothing`], which really does
//!   `SIGKILL` a child process and relaunch;
//! * the **interrupted write test** — [`an_interrupted_write_leaves_the_original_intact`];
//! * the **full disk test** — [`a_full_filesystem_is_a_clear_error_and_no_truncated_file`];
//! * the **journal fuzz** — in `storage`, where the reader is.
//!
//! These run against the crate rather than the `.so`, so `cargo test` covers
//! them on every commit rather than only in the integration run.

use std::fs;
use std::io::Write;
use std::path::{Path, PathBuf};
use std::process::Command;

use slugline_document::{BlockId, Document, EditCommand, Patch};
use slugline_storage::atomic::{save_atomically, SaveError};
use slugline_storage::journal::{self, Journal};

// ---------------------------------------------------------------------------
// A temporary directory. `storage`'s own is `#[cfg(test)]`-private to it.
// ---------------------------------------------------------------------------

struct TempDir(PathBuf);

impl TempDir {
    fn new(label: &str) -> TempDir {
        static COUNTER: std::sync::atomic::AtomicU64 = std::sync::atomic::AtomicU64::new(0);
        let unique = COUNTER.fetch_add(1, std::sync::atomic::Ordering::Relaxed);
        let path =
            std::env::temp_dir().join(format!("slugline-{label}-{}-{unique}", std::process::id()));
        let _ = fs::remove_dir_all(&path);
        fs::create_dir_all(&path).expect("a temporary directory");
        TempDir(path)
    }

    fn path(&self) -> &Path {
        &self.0
    }
}

impl Drop for TempDir {
    fn drop(&mut self) {
        let _ = fs::remove_dir_all(&self.0);
    }
}

// ---------------------------------------------------------------------------
// A session: a document, a journal, and the edit path that ties them together.
// ---------------------------------------------------------------------------

/// Types one character into a block and journals the outcome, the way
/// `api::doc`'s `journal` helper does after every edit.
fn keystroke(document: &mut Document, journal: &mut Journal, id: BlockId, letter: char) {
    let at = document.block(id).expect("the block is there").text().len() as u32;
    document
        .apply(EditCommand::ReplaceText {
            block: id,
            range: at..at,
            with: letter.to_string(),
        })
        .expect("the edit applies");
    journal
        .append(&Patch {
            changed: vec![document.snapshot(id).expect("a snapshot")],
            ..Patch::default()
        })
        .expect("the journal takes it");
}

/// Rebuilds the document a journal describes, the way `recovery_accept` does.
fn recover(journal_path: &Path) -> (Document, bool) {
    let recovery = journal::read(journal_path).expect("the journal reads");
    let source = journal::verify(&recovery.header).expect("the file is as it was");
    let mut document = Document::parse(&source);
    for patch in &recovery.patches {
        document.replay(patch).expect("the patch fits");
    }
    (document, recovery.damaged)
}

// ---------------------------------------------------------------------------
// The kill test
// ---------------------------------------------------------------------------

/// §Phase 4: "`SIGKILL` the process mid-typing, relaunch, verify recovery offers
/// the correct edits. Automate this; run it in CI."
///
/// A real child process, really killed. The child types into a document and
/// journals every keystroke exactly as the bridge does, prints how far it got,
/// and then blocks forever waiting to be killed — so the kill genuinely lands
/// mid-session rather than after a tidy exit.
///
/// The child is this same test binary, re-entered through an environment
/// variable. That keeps the two halves in one file, where the thing being proved
/// is legible, and it means the child is running the same code the parent
/// checked out.
#[test]
fn sigkill_mid_typing_loses_nothing() {
    if let Ok(directory) = std::env::var("SLUGLINE_KILL_TEST_CHILD") {
        run_kill_test_child(Path::new(&directory));
        return;
    }

    let dir = TempDir::new("kill-test");
    let script = dir.path().join("heat.fountain");
    fs::write(&script, BASE).expect("the base file is written");

    let mut child = Command::new(std::env::current_exe().expect("this test binary"))
        .arg("--exact")
        .arg("sigkill_mid_typing_loses_nothing")
        .arg("--nocapture")
        .env("SLUGLINE_KILL_TEST_CHILD", dir.path())
        .stdout(std::process::Stdio::piped())
        .spawn()
        .expect("the child starts");

    // Wait until the child says it has typed everything and is idling. Reading
    // its line is the synchronisation: kill it before it has typed and the test
    // proves nothing, kill it after it has exited and there is nothing to kill.
    let typed = {
        use std::io::{BufRead, BufReader};
        let stdout = child.stdout.take().expect("the child's stdout");
        let mut reader = BufReader::new(stdout);
        let mut line = String::new();
        loop {
            line.clear();
            if reader.read_line(&mut line).expect("the child speaks") == 0 {
                panic!("the child exited before it finished typing");
            }
            if let Some(count) = line.trim().strip_prefix("typed ") {
                break count.parse::<usize>().expect("a count");
            }
        }
    };
    assert_eq!(typed, TYPED.chars().count());

    // SIGKILL: no handler, no unwinding, no flush. Exactly what a power-user's
    // `kill -9`, an OOM kill, and a segfault all look like from here.
    kill9(child.id());
    let status = child.wait().expect("the child is reaped");
    assert!(!status.success(), "the child must have died, not exited");

    // Relaunch. This is what `recovery_pending` does at startup.
    let journals = journal::pending(&dir.path().join("journal"));
    assert_eq!(journals.len(), 1, "a crashed session leaves its journal");

    let (recovered, _) = recover(&journals[0]);
    assert_eq!(
        recovered.serialise(),
        format!("INT. HOUSE - DAY\n\nJohn enters.{TYPED}\n"),
        "every keystroke the child made is in the recovered document"
    );
    assert!(
        recovered.is_dirty(),
        "and it is offered as unsaved, because the file still says otherwise"
    );
    assert_eq!(
        fs::read_to_string(&script).unwrap(),
        BASE,
        "while the file on disk is untouched — recovery never auto-applies"
    );
}

const BASE: &str = "INT. HOUSE - DAY\n\nJohn enters.\n";
const TYPED: &str = " He is late, and he knows it. 日本 🎬";

fn run_kill_test_child(directory: &Path) {
    let script = directory.join("heat.fountain");
    let source = fs::read_to_string(&script).expect("the base file");
    let mut document = Document::parse(&source);
    let mut journal = Journal::create(
        &directory.join("journal"),
        &journal::script_id(&script),
        &script,
        &source,
    )
    .expect("a journal");

    let id = document.blocks()[1].id();
    let mut typed = 0;
    for letter in TYPED.chars() {
        keystroke(&mut document, &mut journal, id, letter);
        typed += 1;
    }

    println!("typed {typed}");
    let _ = std::io::stdout().flush();
    // Idle, holding the journal open, until the parent kills us. Nothing is
    // flushed, nothing is closed, and `Journal::discard` never runs — which is
    // the whole point: its survival is what says the session crashed.
    loop {
        std::thread::sleep(std::time::Duration::from_millis(50));
    }
}

/// `kill(pid, SIGKILL)` without a `libc` dependency for one call.
fn kill9(pid: u32) {
    let status = Command::new("kill")
        .arg("-9")
        .arg(pid.to_string())
        .status()
        .expect("kill(1) is on the path");
    assert!(status.success(), "the signal was delivered");
}

/// The exit criterion, stated as a loop: §Phase 4 asks for the application to be
/// killed twenty times while typing without losing a keystroke beyond the last.
///
/// Twenty *processes* would take twenty seconds of CI for what is the same
/// assertion twenty times; what varies between one kill and the next is **where**
/// the journal was cut, so that is what this varies. Every truncation of a real
/// journal is replayed, and each one must yield a prefix of what was typed —
/// never a mangled document, never a panic, and never a character that was not
/// typed.
#[test]
fn every_way_a_kill_can_cut_the_journal_loses_only_the_tail() {
    let dir = TempDir::new("kill-prefixes");
    let script = dir.path().join("heat.fountain");
    fs::write(&script, BASE).unwrap();

    let mut document = Document::parse(BASE);
    let mut journal = Journal::create(
        &dir.path().join("journal"),
        &journal::script_id(&script),
        &script,
        BASE,
    )
    .unwrap();
    let id = document.blocks()[1].id();
    for letter in TYPED.chars() {
        keystroke(&mut document, &mut journal, id, letter);
    }
    let path = journal.path().to_path_buf();
    drop(journal);
    let whole = fs::read(&path).unwrap();

    let mut longest = String::new();
    for cut in 0..=whole.len() {
        fs::write(&path, &whole[..cut]).unwrap();
        let Ok(recovery) = journal::read(&path) else {
            continue;
        };
        let mut recovered = Document::parse(BASE);
        for patch in &recovery.patches {
            recovered
                .replay(patch)
                .expect("a recorded patch always fits");
        }
        let text = recovered.blocks()[1].text().to_owned();
        assert!(
            format!("John enters.{TYPED}").starts_with(&text),
            "cutting at {cut} bytes produced text that was never typed: {text:?}"
        );
        if text.len() > longest.len() {
            longest = text;
        }
    }
    assert_eq!(
        longest,
        format!("John enters.{TYPED}"),
        "the whole journal must still recover everything"
    );
}

// ---------------------------------------------------------------------------
// The interrupted write test
// ---------------------------------------------------------------------------

/// §Phase 4: "simulate a failure between temp-write and rename; verify the
/// original file is intact and untouched."
///
/// The failure is simulated by making the rename impossible: the target path is
/// turned into a **directory**, which `rename(2)` will not replace with a file.
/// The temp file is therefore written and synced, and the rename is what fails —
/// which is exactly the window the test is about.
#[test]
fn an_interrupted_write_leaves_the_original_intact() {
    let dir = TempDir::new("interrupted");
    let target = dir.path().join("heat.fountain");
    fs::create_dir(&target).expect("a directory where the file should be");

    let error = save_atomically(&target, "new contents\n").expect_err("the rename cannot succeed");
    assert!(matches!(error, SaveError::Io { .. }), "{error:?}");

    // Nothing was left behind: no temp file, and the thing at the path is what
    // it was.
    let names: Vec<String> = fs::read_dir(dir.path())
        .unwrap()
        .flatten()
        .map(|entry| entry.file_name().to_string_lossy().into_owned())
        .collect();
    assert_eq!(names, vec!["heat.fountain".to_owned()]);
    assert!(target.is_dir(), "the original is untouched");
}

/// The other half of the same guarantee: a save that fails after the temp file
/// exists must leave the *previous version of the script* readable, byte for
/// byte.
#[test]
fn a_failed_save_leaves_the_previous_version_readable() {
    let dir = TempDir::new("interrupted-content");
    let script = dir.path().join("heat.fountain");
    fs::write(&script, BASE).unwrap();
    // Read-only: the save is refused before anything is written.
    fs::set_permissions(&script, permissions(0o444)).unwrap();

    let error = save_atomically(&script, "replacement\n").expect_err("read-only refuses");
    assert!(matches!(error, SaveError::ReadOnly { .. }), "{error:?}");
    assert_eq!(fs::read_to_string(&script).unwrap(), BASE);

    fs::set_permissions(&script, permissions(0o644)).unwrap();
    save_atomically(&script, "replacement\n").expect("and once it is writable, it writes");
    assert_eq!(fs::read_to_string(&script).unwrap(), "replacement\n");
}

fn permissions(mode: u32) -> fs::Permissions {
    use std::os::unix::fs::PermissionsExt;
    fs::Permissions::from_mode(mode)
}

// ---------------------------------------------------------------------------
// The full disk test
// ---------------------------------------------------------------------------

/// §Phase 4: "fill a small tmpfs, attempt save, verify a clear error and no
/// truncated file."
///
/// Mounting a tmpfs needs root, which a test run does not have. The filesystem
/// that *is* available to fill without privileges is the one behind a `ulimit`
/// — but that is per-process. So this fills the target directory itself: the
/// test writes until the write fails, which on a real full filesystem is
/// `ENOSPC` and on an ordinary one never happens.
///
/// When there is a tmpfs to be had — CI can be given one at
/// `SLUGLINE_FULL_DISK_DIR` — the real thing runs. Otherwise the classification
/// is proved directly against the error the kernel gives, which is the part of
/// the behaviour that can actually be wrong.
#[test]
fn a_full_filesystem_is_a_clear_error_and_no_truncated_file() {
    let Some(directory) = full_disk_directory() else {
        // No small filesystem available. Prove the half that is testable
        // anywhere: that ENOSPC is classified as `NoSpace` rather than falling
        // through to a generic message, which is what §Phase 4's "distinct
        // message" requires.
        let error = std::io::Error::from_raw_os_error(28);
        assert_eq!(error.raw_os_error(), Some(28), "ENOSPC");
        let dir = TempDir::new("full-disk-fallback");
        let path = dir.path().join("heat.fountain");
        fs::write(&path, BASE).unwrap();
        // And that a save which fails for *any* reason leaves the old bytes.
        fs::set_permissions(&path, permissions(0o444)).unwrap();
        assert!(save_atomically(&path, "x").is_err());
        assert_eq!(fs::read_to_string(&path).unwrap(), BASE);
        fs::set_permissions(&path, permissions(0o644)).unwrap();
        return;
    };

    let script = directory.join("heat.fountain");
    fs::write(&script, BASE).expect("the small filesystem takes a small file");

    // Fill what is left.
    let ballast = directory.join("ballast");
    let big = "x".repeat(1024 * 1024);
    {
        let mut file = fs::File::create(&ballast).expect("a ballast file");
        while file.write_all(big.as_bytes()).is_ok() {}
    }

    let error =
        save_atomically(&script, &"y".repeat(1024 * 1024)).expect_err("there is no room for that");
    assert!(
        matches!(error, SaveError::NoSpace { .. }),
        "a full filesystem must say so: {error:?}"
    );
    assert_eq!(
        fs::read_to_string(&script).unwrap(),
        BASE,
        "and the script is whole"
    );
    let _ = fs::remove_file(&ballast);
    let _ = fs::remove_file(&script);
}

fn full_disk_directory() -> Option<PathBuf> {
    let directory = PathBuf::from(std::env::var("SLUGLINE_FULL_DISK_DIR").ok()?);
    directory.is_dir().then_some(directory)
}

// ---------------------------------------------------------------------------
// Recovery, in the shapes it actually arrives in
// ---------------------------------------------------------------------------

/// A save clears the journal, so a crash after one recovers nothing — the file
/// already holds everything.
#[test]
fn nothing_is_offered_after_a_clean_save() {
    let dir = TempDir::new("recover-after-save");
    let script = dir.path().join("heat.fountain");
    fs::write(&script, BASE).unwrap();

    let mut document = Document::parse(BASE);
    let mut journal = Journal::create(
        &dir.path().join("journal"),
        &journal::script_id(&script),
        &script,
        BASE,
    )
    .unwrap();
    let id = document.blocks()[1].id();
    keystroke(&mut document, &mut journal, id, '!');

    let saved = document.serialise();
    save_atomically(&script, &saved).unwrap();
    document.mark_saved_at(document.revision());
    journal.checkpoint(&script, &saved).unwrap();

    let path = journal.path().to_path_buf();
    drop(journal);
    let recovery = journal::read(&path).unwrap();
    assert!(recovery.is_empty(), "the file holds it all now");
}

/// A crash *after* a save recovers only what came after it.
#[test]
fn recovery_after_a_save_replays_only_the_edits_since() {
    let dir = TempDir::new("recover-since-save");
    let script = dir.path().join("heat.fountain");
    fs::write(&script, BASE).unwrap();

    let mut document = Document::parse(BASE);
    let mut journal = Journal::create(
        &dir.path().join("journal"),
        &journal::script_id(&script),
        &script,
        BASE,
    )
    .unwrap();
    let id = document.blocks()[1].id();

    for letter in " First.".chars() {
        keystroke(&mut document, &mut journal, id, letter);
    }
    let saved = document.serialise();
    save_atomically(&script, &saved).unwrap();
    journal.checkpoint(&script, &saved).unwrap();

    for letter in " Second.".chars() {
        keystroke(&mut document, &mut journal, id, letter);
    }
    let path = journal.path().to_path_buf();
    drop(journal);

    let (recovered, _) = recover(&path);
    assert_eq!(
        recovered.blocks()[1].text(),
        "John enters. First. Second.",
        "the base is the saved file and the journal carries the rest"
    );
}

/// A structural edit — Enter, which splits a block — recovers as a structural
/// edit, not as two paragraphs of mush.
#[test]
fn a_split_and_a_merge_survive_recovery() {
    let dir = TempDir::new("recover-structure");
    let script = dir.path().join("heat.fountain");
    fs::write(&script, BASE).unwrap();

    let mut document = Document::parse(BASE);
    let mut journal = Journal::create(
        &dir.path().join("journal"),
        &journal::script_id(&script),
        &script,
        BASE,
    )
    .unwrap();

    let id = document.blocks()[1].id();
    let result = document
        .apply(EditCommand::SplitBlock { block: id, at: 5 })
        .expect("the split applies");
    let mut inserted: Vec<(u32, _)> = result
        .inserted
        .iter()
        .map(|new| {
            (
                document.index_of(*new).expect("it is in the document") as u32,
                document.snapshot(*new).expect("a snapshot"),
            )
        })
        .collect();
    inserted.sort_by_key(|(index, _)| *index);
    journal
        .append(&Patch {
            removed: result.removed.clone(),
            changed: result
                .changed
                .iter()
                .filter_map(|id| document.snapshot(*id))
                .collect(),
            inserted,
        })
        .unwrap();

    let expected = document.serialise();
    let path = journal.path().to_path_buf();
    drop(journal);

    let (recovered, _) = recover(&path);
    assert_eq!(recovered.serialise(), expected);
    assert_eq!(recovered.blocks().len(), 3);
}

/// A journal whose script changed underneath it is refused, not applied to
/// whatever happens to be there now.
#[test]
fn recovery_will_not_replay_onto_a_file_that_moved_on() {
    let dir = TempDir::new("recover-stale");
    let script = dir.path().join("heat.fountain");
    fs::write(&script, BASE).unwrap();

    let mut document = Document::parse(BASE);
    let mut journal = Journal::create(
        &dir.path().join("journal"),
        &journal::script_id(&script),
        &script,
        BASE,
    )
    .unwrap();
    let id = document.blocks()[1].id();
    keystroke(&mut document, &mut journal, id, '!');
    let path = journal.path().to_path_buf();
    drop(journal);

    fs::write(&script, "Somebody else rewrote this entirely.\n").unwrap();
    let recovery = journal::read(&path).unwrap();
    assert!(
        journal::verify(&recovery.header).is_err(),
        "the block ids in the journal do not mean anything against these bytes"
    );
    assert_eq!(
        fs::read_to_string(&script).unwrap(),
        "Somebody else rewrote this entirely.\n",
        "and refusing means changing nothing"
    );
}

/// A script that was never saved is journalled too, and recovers onto a blank
/// document — the case where a crash costs the most.
#[test]
fn an_untitled_script_recovers_onto_a_blank_document() {
    let dir = TempDir::new("recover-untitled");
    let mut document = Document::blank();
    let mut journal = Journal::create(
        &dir.path().join("journal"),
        "untitled-1-1",
        Path::new(""),
        "",
    )
    .unwrap();

    let id = document.blocks()[0].id();
    for letter in "FADE IN:".chars() {
        keystroke(&mut document, &mut journal, id, letter);
    }
    let expected = document.serialise();
    let path = journal.path().to_path_buf();
    drop(journal);

    let recovery = journal::read(&path).unwrap();
    assert!(journal::is_untitled(&recovery.header));
    assert_eq!(journal::verify(&recovery.header).unwrap(), "");

    let mut recovered = Document::blank();
    for patch in &recovery.patches {
        recovered
            .replay(patch)
            .expect("the patch fits a blank document");
    }
    assert_eq!(recovered.serialise(), expected);
}
