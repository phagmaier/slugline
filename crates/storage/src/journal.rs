//! The append-only edit journal of §Phase 4, and crash recovery from it.
//!
//! ## What it is for
//!
//! An autosave every two seconds still leaves two seconds of typing in memory
//! only. The journal closes that window: every edit is appended to a file the
//! moment it is applied, so what survives a `SIGKILL` is everything up to and
//! including the keystroke that was in flight.
//!
//! ## The format
//!
//! One JSON object per line. The first line is a header naming the file the
//! journal was recorded against; every line after it is one [`Patch`], in the
//! order it was applied.
//!
//! ```text
//! {"version":1,"script":"/home/writer/heat.fountain","base":"3f2a…","records":0}
//! {"seq":1,"changed":[{"id":4,"kind":"action","text":"John enters","forced":false,"dual":false}]}
//! {"seq":2,"changed":[{"id":4,"kind":"action","text":"John enters.","forced":false,"dual":false}]}
//! ```
//!
//! JSON because §2.6 already chose `serde_json` for the files a user might have
//! to look at, and a journal is exactly such a file: when recovery goes wrong,
//! the writer's text is *in there* and they must be able to get it out with a
//! text editor. Line-delimited because a partially written last line is then
//! trivially detectable — it has no newline — and discardable without touching
//! anything before it.
//!
//! ## Durability
//!
//! Appends are written but **not** `fsync`ed. This is deliberate and it is the
//! difference between a journal that costs nothing and one that costs a disk
//! round trip per keystroke. The threat model §Phase 4 names is the process
//! dying — `SIGKILL`, a panic, an OOM kill — and a `write(2)` that has returned
//! has already reached the kernel, so the data survives all of those whether or
//! not it has reached the platter. Power loss can still lose the tail of the
//! journal; the atomic save in [`crate::atomic`] is what protects the file
//! itself against that, and no amount of `fsync` here would make the last
//! keystroke before a power cut survivable anyway.
//!
//! ## Reading it back
//!
//! [`read`] is total in the same sense the Fountain parser is: no input makes it
//! fail. A truncated, corrupt, or half-written journal yields the records it
//! could read and says that it stopped early. §Phase 4 requires this by test
//! ("fuzz the journal … must not crash recovery"), and the reason is worth
//! stating: a journal is read at exactly the moment the user has already lost
//! something, and a recovery path that panics on a damaged file is a recovery
//! path that turns a bad day into a lost script.

use std::fs::{self, File, OpenOptions};
use std::io::{self, Write};
use std::path::{Path, PathBuf};

use serde::{Deserialize, Serialize};
use slugline_document::{BlockId, BlockKind, BlockSnapshot, Patch};

/// Bumped if the record shape ever changes. A journal from a future version is
/// not replayed — it is left alone and reported, so that a downgrade cannot
/// quietly drop half a session.
const FORMAT_VERSION: u32 = 1;

// ---------------------------------------------------------------------------
// On-disk shapes
// ---------------------------------------------------------------------------

/// The first line of a journal.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct Header {
    pub version: u32,
    /// The file this journal's records apply to.
    pub script: PathBuf,
    /// A checksum of that file's contents as they were when the journal was
    /// opened. Recovery refuses to replay onto a file that has changed
    /// underneath it — the records name blocks by the identity a parse of
    /// *those* bytes gives them.
    pub base: String,
}

/// One block, as a line of JSON.
///
/// A mirror of [`BlockSnapshot`] rather than a `Serialize` derive on it, so that
/// `document` and `fountain` stay free of `serde` — they are the two crates §2.5
/// keeps pure, and a file format is not a thing the model should know about. The
/// cost is the two conversions below and a test that walks every kind through
/// them.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
struct RecordBlock {
    id: u64,
    kind: String,
    #[serde(default, skip_serializing_if = "is_zero")]
    level: u8,
    text: String,
    #[serde(default, skip_serializing_if = "is_false")]
    forced: bool,
    #[serde(default, skip_serializing_if = "is_false")]
    dual: bool,
}

fn is_zero(value: &u8) -> bool {
    *value == 0
}

fn is_false(value: &bool) -> bool {
    !*value
}

/// One line of a journal after the header: what one edit did.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
struct Record {
    seq: u64,
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    removed: Vec<u64>,
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    changed: Vec<RecordBlock>,
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    inserted: Vec<(u32, RecordBlock)>,
}

impl RecordBlock {
    fn of(snapshot: &BlockSnapshot) -> RecordBlock {
        let (kind, level) = encode_kind(snapshot.kind);
        RecordBlock {
            id: snapshot.id.0,
            kind: kind.to_owned(),
            level,
            text: snapshot.text.clone(),
            forced: snapshot.forced,
            dual: snapshot.dual,
        }
    }

    /// `None` for a kind this version does not know. An unreadable block ends
    /// the readable run rather than being guessed at.
    fn to_snapshot(&self) -> Option<BlockSnapshot> {
        Some(BlockSnapshot {
            id: BlockId(self.id),
            kind: decode_kind(&self.kind, self.level)?,
            text: self.text.clone(),
            forced: self.forced,
            dual: self.dual,
        })
    }
}

/// Element types, as names rather than numbers.
///
/// A number would be shorter and would be a trap: inserting a variant into
/// `BlockKind` would silently reinterpret every journal on every disk. Names
/// cannot drift, and they are also what makes the file readable by hand, which
/// is the point of choosing JSON at all.
fn encode_kind(kind: BlockKind) -> (&'static str, u8) {
    match kind {
        BlockKind::SceneHeading => ("scene_heading", 0),
        BlockKind::Action => ("action", 0),
        BlockKind::Character => ("character", 0),
        BlockKind::Dialogue => ("dialogue", 0),
        BlockKind::Parenthetical => ("parenthetical", 0),
        BlockKind::Transition => ("transition", 0),
        BlockKind::Centered => ("centered", 0),
        BlockKind::Lyric => ("lyric", 0),
        BlockKind::Section { level } => ("section", level),
        BlockKind::Synopsis => ("synopsis", 0),
        BlockKind::Note => ("note", 0),
        BlockKind::PageBreak => ("page_break", 0),
        BlockKind::Opaque => ("opaque", 0),
    }
}

fn decode_kind(name: &str, level: u8) -> Option<BlockKind> {
    Some(match name {
        "scene_heading" => BlockKind::SceneHeading,
        "action" => BlockKind::Action,
        "character" => BlockKind::Character,
        "dialogue" => BlockKind::Dialogue,
        "parenthetical" => BlockKind::Parenthetical,
        "transition" => BlockKind::Transition,
        "centered" => BlockKind::Centered,
        "lyric" => BlockKind::Lyric,
        "section" => BlockKind::Section {
            level: level.clamp(1, 6),
        },
        "synopsis" => BlockKind::Synopsis,
        "note" => BlockKind::Note,
        "page_break" => BlockKind::PageBreak,
        "opaque" => BlockKind::Opaque,
        _ => return None,
    })
}

// ---------------------------------------------------------------------------
// Writing
// ---------------------------------------------------------------------------

/// An open journal for one script.
///
/// The file handle is held open for the session. Reopening per append would be
/// three syscalls instead of one on the keystroke path, and would race with a
/// checkpoint truncating the file underneath it.
pub struct Journal {
    file: File,
    path: PathBuf,
    seq: u64,
    records: u64,
}

impl Journal {
    /// Starts a journal for `script`, whose contents are currently `base`.
    ///
    /// `script` is empty for a script that has never been saved. Such a session
    /// still gets a journal — it is the one a crash hurts most — and recovery
    /// replays it onto [`Document::blank`] rather than onto a file. `id` is what
    /// names the file, so the caller can keep two untitled sessions apart.
    ///
    /// Replaces any journal already at that name. There is only ever one live
    /// session per script, and a leftover journal has either been recovered from
    /// or been declined — [`pending`] is what finds one *before* this is called.
    pub fn create(dir: &Path, id: &str, script: &Path, base: &str) -> io::Result<Journal> {
        fs::create_dir_all(dir)?;
        let path = dir.join(format!("{id}.log"));
        let mut file = OpenOptions::new()
            .write(true)
            .create(true)
            .truncate(true)
            .open(&path)?;
        write_header(
            &mut file,
            &Header {
                version: FORMAT_VERSION,
                script: script.to_path_buf(),
                base: checksum(base),
            },
        )?;
        Ok(Journal {
            file,
            path,
            seq: 0,
            records: 0,
        })
    }

    /// Records what one edit did. Nothing is recorded for an edit that changed
    /// nothing.
    pub fn append(&mut self, patch: &Patch) -> io::Result<()> {
        if patch.is_empty() {
            return Ok(());
        }
        self.seq += 1;
        let record = Record {
            seq: self.seq,
            removed: patch.removed.iter().map(|id| id.0).collect(),
            changed: patch.changed.iter().map(RecordBlock::of).collect(),
            inserted: patch
                .inserted
                .iter()
                .map(|(index, block)| (*index, RecordBlock::of(block)))
                .collect(),
        };
        // One `write_all` for the line and its terminator together. Two writes
        // could be interrupted between them, and a line without its newline is
        // exactly what the reader treats as damage.
        let mut line = serde_json::to_vec(&record).map_err(io::Error::other)?;
        line.push(b'\n');
        self.file.write_all(&line)?;
        self.records += 1;
        Ok(())
    }

    /// Starts the journal over against newly written bytes. Called after every
    /// successful save: the records before it describe edits that are now in the
    /// file, and replaying them onto it would apply them twice.
    pub fn checkpoint(&mut self, script: &Path, base: &str) -> io::Result<()> {
        self.file.set_len(0)?;
        self.file.seek_start()?;
        write_header(
            &mut self.file,
            &Header {
                version: FORMAT_VERSION,
                script: script.to_path_buf(),
                base: checksum(base),
            },
        )?;
        self.seq = 0;
        self.records = 0;
        Ok(())
    }

    /// Ends the session cleanly: the journal is removed.
    ///
    /// Its *absence* is what says the previous session ended properly, so this
    /// is the one operation that must happen on a clean close and must not
    /// happen any other time.
    pub fn discard(self) -> io::Result<()> {
        drop(self.file);
        match fs::remove_file(&self.path) {
            Err(error) if error.kind() == io::ErrorKind::NotFound => Ok(()),
            other => other,
        }
    }

    /// How many edits are recorded since the last checkpoint. This is the
    /// number §Phase 4's recovery prompt shows — "14 edits since last save".
    pub fn records(&self) -> u64 {
        self.records
    }

    pub fn path(&self) -> &Path {
        &self.path
    }
}

/// `File::set_len` leaves the cursor where it was, which after a truncation is
/// past the end — and writing there would leave a hole full of zero bytes in
/// front of the header.
trait SeekStart {
    fn seek_start(&mut self) -> io::Result<()>;
}

impl SeekStart for File {
    fn seek_start(&mut self) -> io::Result<()> {
        use std::io::Seek;
        self.seek(io::SeekFrom::Start(0)).map(drop)
    }
}

fn write_header(file: &mut File, header: &Header) -> io::Result<()> {
    let mut line = serde_json::to_vec(header).map_err(io::Error::other)?;
    line.push(b'\n');
    file.write_all(&line)
}

// ---------------------------------------------------------------------------
// Reading
// ---------------------------------------------------------------------------

/// A journal found on disk, as much of it as could be read.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Recovery {
    pub header: Header,
    /// The patches to replay, in order.
    pub patches: Vec<Patch>,
    /// Whether reading stopped before the end of the file.
    ///
    /// True after a `SIGKILL` caught mid-write, which is the ordinary case and
    /// not a problem: the damage is always the last line, and the records before
    /// it are intact. Surfaced anyway, because "we recovered 14 of your edits
    /// and could not read the 15th" is a different sentence from "we recovered
    /// your edits".
    pub damaged: bool,
    pub path: PathBuf,
}

impl Recovery {
    /// Whether there is anything to offer the user.
    pub fn is_empty(&self) -> bool {
        self.patches.is_empty()
    }
}

/// Why a journal file could not be used at all.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum JournalError {
    /// Not a journal, or its header is unreadable. Nothing can be recovered.
    Unreadable,
    /// Written by a newer version of Slugline.
    FromTheFuture { version: u32 },
    /// The script it names is not there any more.
    ScriptMissing { script: PathBuf },
    /// The script has changed since the journal was opened; the block ids in the
    /// records would not mean what they meant when they were written.
    ScriptChanged { script: PathBuf },
}

impl std::fmt::Display for JournalError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            JournalError::Unreadable => write!(f, "the recovery record is unreadable"),
            JournalError::FromTheFuture { version } => {
                write!(f, "the recovery record is from a newer version ({version})")
            }
            JournalError::ScriptMissing { script } => {
                write!(f, "{} is no longer there", script.display())
            }
            JournalError::ScriptChanged { script } => {
                write!(f, "{} has changed since it was last open", script.display())
            }
        }
    }
}

impl std::error::Error for JournalError {}

/// Reads a journal file. Never panics, whatever the file holds.
///
/// A record counts only if it was written **whole**, and "whole" means it was
/// followed by a newline. That is the entire integrity scheme, and it is enough
/// because [`Journal::append`] writes each record and its terminator in one
/// `write_all`: a record with a newline after it is a record the kernel took in
/// full.
pub fn read(path: &Path) -> Result<Recovery, JournalError> {
    let bytes = fs::read(path).map_err(|_| JournalError::Unreadable)?;
    let mut lines: Vec<&[u8]> = bytes.split(|byte| *byte == b'\n').collect();

    // The tail after the last newline. Empty for a file that ends in one;
    // anything else is a write that was interrupted, which is what a `SIGKILL`
    // mid-keystroke leaves behind.
    let mut damaged = matches!(lines.pop(), Some(tail) if !tail.is_empty());

    let mut lines = lines.into_iter();
    let header: Header = lines
        .next()
        .and_then(|line| serde_json::from_slice(line).ok())
        .ok_or(JournalError::Unreadable)?;
    if header.version != FORMAT_VERSION {
        return Err(JournalError::FromTheFuture {
            version: header.version,
        });
    }

    let mut patches = Vec::new();
    for line in lines {
        if line.is_empty() {
            continue;
        }
        // Anything that does not read cleanly ends the run. A record after a
        // damaged one is not applied even if it parses: whatever it was built on
        // top of is the record that did not.
        let Some(patch) = serde_json::from_slice::<Record>(line)
            .ok()
            .and_then(to_patch)
        else {
            damaged = true;
            break;
        };
        patches.push(patch);
    }

    Ok(Recovery {
        header,
        patches,
        damaged,
        path: path.to_path_buf(),
    })
}

fn to_patch(record: Record) -> Option<Patch> {
    let mut changed = Vec::with_capacity(record.changed.len());
    for block in &record.changed {
        changed.push(block.to_snapshot()?);
    }
    let mut inserted = Vec::with_capacity(record.inserted.len());
    for (index, block) in &record.inserted {
        inserted.push((*index, block.to_snapshot()?));
    }
    Some(Patch {
        removed: record.removed.into_iter().map(BlockId).collect(),
        changed,
        inserted,
    })
}

/// Whether a journal belongs to a script that was never saved.
pub fn is_untitled(header: &Header) -> bool {
    header.script.as_os_str().is_empty()
}

/// Checks a journal against the script it names, without reading its records.
///
/// Separated from [`read`] because it is the question the *startup* path asks —
/// "is this worth offering?" — and it is the one that touches the user's own
/// files.
///
/// An untitled journal has no file to check against and no base to return: its
/// records replay onto a blank document, whose shape is fixed by the model.
pub fn verify(header: &Header) -> Result<String, JournalError> {
    if is_untitled(header) {
        return Ok(String::new());
    }
    let source = fs::read_to_string(&header.script).map_err(|_| JournalError::ScriptMissing {
        script: header.script.clone(),
    })?;
    if checksum(&source) != header.base {
        return Err(JournalError::ScriptChanged {
            script: header.script.clone(),
        });
    }
    Ok(source)
}

/// Every journal left behind in `dir`.
///
/// A journal that exists at startup is a session that did not end cleanly:
/// [`Journal::discard`] removes the file, and nothing else does. Sorted, so that
/// two runs of the same recovery offer the same order.
pub fn pending(dir: &Path) -> Vec<PathBuf> {
    let mut found: Vec<PathBuf> = fs::read_dir(dir)
        .into_iter()
        .flatten()
        .flatten()
        .map(|entry| entry.path())
        .filter(|path| path.extension().is_some_and(|extension| extension == "log"))
        .collect();
    found.sort();
    found
}

/// Removes a journal the user declined to recover from.
pub fn discard_at(path: &Path) -> io::Result<()> {
    match fs::remove_file(path) {
        Err(error) if error.kind() == io::ErrorKind::NotFound => Ok(()),
        other => other,
    }
}

// ---------------------------------------------------------------------------
// Identity
// ---------------------------------------------------------------------------

/// A stable name for a script, from its path.
///
/// Used for the journal's file name and for the backup directory's. A hash
/// rather than the path itself because a path contains `/` and may be longer
/// than a file name may be, and because a script's own name has no business
/// being visible in a state directory the user did not choose to fill.
pub fn script_id(path: &Path) -> String {
    format!("{:016x}", fnv1a(path.as_os_str().as_encoded_bytes()))
}

/// FNV-1a, 64-bit.
///
/// Not a cryptographic hash and not asked to be one. Both jobs here — naming a
/// file after a path, and noticing that a file changed under us — need a
/// collision to be unlikely, not a collision to be unfindable. The alternative
/// was a dependency for six lines.
fn fnv1a(bytes: &[u8]) -> u64 {
    let mut hash: u64 = 0xcbf2_9ce4_8422_2325;
    for byte in bytes {
        hash ^= *byte as u64;
        hash = hash.wrapping_mul(0x0000_0100_0000_01b3);
    }
    hash
}

/// The checksum a journal header carries, as hex. Length is mixed in so that
/// two files cannot agree by hash alone.
pub fn checksum(contents: &str) -> String {
    format!("{:016x}-{}", fnv1a(contents.as_bytes()), contents.len())
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::testing::TempDir;
    use slugline_document::Document;

    fn snapshot(id: u64, kind: BlockKind, text: &str) -> BlockSnapshot {
        BlockSnapshot {
            id: BlockId(id),
            kind,
            text: text.to_owned(),
            forced: false,
            dual: false,
        }
    }

    fn change(id: u64, text: &str) -> Patch {
        Patch {
            changed: vec![snapshot(id, BlockKind::Action, text)],
            ..Patch::default()
        }
    }

    #[test]
    fn every_element_kind_survives_the_round_trip() {
        // The one thing the hand-written mirror can get wrong, held to by test:
        // a kind that encodes to a name nothing decodes would silently truncate
        // a recovery at the first block of that kind.
        let kinds = [
            BlockKind::SceneHeading,
            BlockKind::Action,
            BlockKind::Character,
            BlockKind::Dialogue,
            BlockKind::Parenthetical,
            BlockKind::Transition,
            BlockKind::Centered,
            BlockKind::Lyric,
            BlockKind::Section { level: 1 },
            BlockKind::Section { level: 6 },
            BlockKind::Synopsis,
            BlockKind::Note,
            BlockKind::PageBreak,
            BlockKind::Opaque,
        ];
        for kind in kinds {
            let original = snapshot(7, kind, "text");
            let round_tripped = RecordBlock::of(&original)
                .to_snapshot()
                .unwrap_or_else(|| panic!("{kind:?} does not decode"));
            assert_eq!(round_tripped, original, "{kind:?}");
        }
    }

    #[test]
    fn an_unknown_kind_stops_the_run_rather_than_being_guessed_at() {
        let block = RecordBlock {
            id: 1,
            kind: "hologram".to_owned(),
            level: 0,
            text: "x".to_owned(),
            forced: false,
            dual: false,
        };
        assert_eq!(block.to_snapshot(), None);
    }

    #[test]
    fn records_read_back_in_the_order_they_were_written() {
        let dir = TempDir::new("journal-order");
        let script = dir.path().join("heat.fountain");
        fs::write(&script, "Action.\n").unwrap();

        let mut journal =
            Journal::create(dir.path(), &script_id(&script), &script, "Action.\n").unwrap();
        for step in 1..=5 {
            journal
                .append(&change(1, &format!("Action {step}")))
                .unwrap();
        }
        assert_eq!(journal.records(), 5);
        let path = journal.path().to_path_buf();
        drop(journal);

        let recovery = read(&path).expect("the journal reads");
        assert_eq!(recovery.patches.len(), 5);
        assert!(!recovery.damaged);
        assert_eq!(recovery.patches[4].changed[0].text, "Action 5");
        assert_eq!(recovery.header.script, script);
    }

    #[test]
    fn an_empty_patch_is_not_recorded() {
        let dir = TempDir::new("journal-empty");
        let script = dir.path().join("x.fountain");
        let mut journal = Journal::create(dir.path(), &script_id(&script), &script, "").unwrap();
        journal.append(&Patch::default()).unwrap();
        assert_eq!(journal.records(), 0);
    }

    #[test]
    fn a_checkpoint_forgets_what_is_already_in_the_file() {
        let dir = TempDir::new("journal-checkpoint");
        let script = dir.path().join("x.fountain");
        let mut journal =
            Journal::create(dir.path(), &script_id(&script), &script, "before").unwrap();
        journal.append(&change(1, "a")).unwrap();
        journal.append(&change(1, "b")).unwrap();
        journal.checkpoint(&script, "after").unwrap();
        journal.append(&change(1, "c")).unwrap();

        let path = journal.path().to_path_buf();
        drop(journal);
        let recovery = read(&path).unwrap();
        assert_eq!(recovery.patches.len(), 1, "only the edits since the save");
        assert_eq!(recovery.patches[0].changed[0].text, "c");
        assert_eq!(recovery.header.base, checksum("after"));
        assert!(!recovery.damaged, "truncation must not leave a hole");
    }

    #[test]
    fn a_clean_close_leaves_nothing_to_recover() {
        let dir = TempDir::new("journal-discard");
        let script = dir.path().join("x.fountain");
        let mut journal = Journal::create(dir.path(), &script_id(&script), &script, "").unwrap();
        journal.append(&change(1, "a")).unwrap();
        journal.discard().unwrap();
        assert!(pending(dir.path()).is_empty());
    }

    #[test]
    fn a_journal_left_behind_is_what_says_the_session_crashed() {
        let dir = TempDir::new("journal-pending");
        let script = dir.path().join("x.fountain");
        let mut journal = Journal::create(dir.path(), &script_id(&script), &script, "").unwrap();
        journal.append(&change(1, "a")).unwrap();
        drop(journal);
        assert_eq!(pending(dir.path()).len(), 1);
    }

    #[test]
    fn a_half_written_last_record_is_dropped_and_the_rest_kept() {
        let dir = TempDir::new("journal-torn");
        let script = dir.path().join("x.fountain");
        let mut journal = Journal::create(dir.path(), &script_id(&script), &script, "").unwrap();
        journal.append(&change(1, "one")).unwrap();
        journal.append(&change(1, "two")).unwrap();
        let path = journal.path().to_path_buf();
        drop(journal);

        // Chop the file mid-record, the way a SIGKILL between two writes would.
        let bytes = fs::read(&path).unwrap();
        fs::write(&path, &bytes[..bytes.len() - 12]).unwrap();

        let recovery = read(&path).expect("a torn journal still reads");
        assert_eq!(recovery.patches.len(), 1);
        assert_eq!(recovery.patches[0].changed[0].text, "one");
        assert!(recovery.damaged);
    }

    #[test]
    fn a_journal_with_only_a_header_recovers_nothing_and_says_so() {
        let dir = TempDir::new("journal-header-only");
        let script = dir.path().join("x.fountain");
        let journal = Journal::create(dir.path(), &script_id(&script), &script, "").unwrap();
        let path = journal.path().to_path_buf();
        drop(journal);
        let recovery = read(&path).unwrap();
        assert!(recovery.is_empty());
        assert!(!recovery.damaged);
    }

    #[test]
    fn a_file_that_is_not_a_journal_is_refused_rather_than_interpreted() {
        let dir = TempDir::new("journal-garbage");
        let path = dir.path().join("nonsense.log");
        fs::write(&path, "this is not JSON at all\n").unwrap();
        assert_eq!(read(&path), Err(JournalError::Unreadable));
    }

    #[test]
    fn a_journal_from_a_newer_version_is_left_alone() {
        let dir = TempDir::new("journal-future");
        let path = dir.path().join("future.log");
        fs::write(&path, "{\"version\":99,\"script\":\"/x\",\"base\":\"y\"}\n").unwrap();
        assert!(matches!(
            read(&path),
            Err(JournalError::FromTheFuture { version: 99 })
        ));
    }

    #[test]
    fn recovery_refuses_a_script_that_changed_underneath_it() {
        let dir = TempDir::new("journal-changed");
        let script = dir.path().join("x.fountain");
        fs::write(&script, "original\n").unwrap();
        let journal =
            Journal::create(dir.path(), &script_id(&script), &script, "original\n").unwrap();
        let path = journal.path().to_path_buf();
        drop(journal);

        fs::write(&script, "somebody else wrote this\n").unwrap();
        let recovery = read(&path).unwrap();
        assert!(matches!(
            verify(&recovery.header),
            Err(JournalError::ScriptChanged { .. })
        ));
    }

    #[test]
    fn replaying_a_journal_reproduces_the_document_that_was_lost() {
        // The whole point, end to end: type into a document, journal every edit,
        // then rebuild it from the file it was opened from plus the journal.
        let dir = TempDir::new("journal-replay");
        let script = dir.path().join("heat.fountain");
        let base = "INT. HOUSE - DAY\n\nJohn enters.\n";
        fs::write(&script, base).unwrap();

        let mut live = Document::parse(base);
        let mut journal = Journal::create(dir.path(), &script_id(&script), &script, base).unwrap();

        let id = live.blocks()[1].id();
        for (offset, letter) in " He is late.".chars().enumerate() {
            let at = 12 + offset as u32;
            live.apply(slugline_document::EditCommand::ReplaceText {
                block: id,
                range: at..at,
                with: letter.to_string(),
            })
            .unwrap();
            journal
                .append(&Patch {
                    changed: vec![live.snapshot(id).unwrap()],
                    ..Patch::default()
                })
                .unwrap();
        }
        let expected = live.serialise();
        let path = journal.path().to_path_buf();
        drop(journal);

        let recovery = read(&path).unwrap();
        let source = verify(&recovery.header).expect("the file is as it was");
        let mut recovered = Document::parse(&source);
        for patch in &recovery.patches {
            recovered.replay(patch).expect("the patch fits");
        }
        assert_eq!(recovered.serialise(), expected);
        assert!(
            recovered.is_dirty(),
            "the file on disk is still the old one"
        );
    }

    #[test]
    fn no_byte_sequence_makes_the_reader_panic() {
        // §Phase 4: "Fuzz the journal: truncated, corrupt, and partially-written
        // records must not crash recovery." A deterministic sweep rather than a
        // fuzzer, so that it runs in CI on every commit: every truncation of a
        // real journal, and then every single-byte corruption of it.
        let dir = TempDir::new("journal-fuzz");
        let script = dir.path().join("x.fountain");
        let mut journal =
            Journal::create(dir.path(), &script_id(&script), &script, "base").unwrap();
        journal.append(&change(1, "héllo 🎬")).unwrap();
        journal
            .append(&Patch {
                removed: vec![BlockId(2)],
                changed: vec![snapshot(1, BlockKind::Section { level: 3 }, "x")],
                inserted: vec![(0, snapshot(9, BlockKind::Dialogue, "y"))],
            })
            .unwrap();
        let path = journal.path().to_path_buf();
        drop(journal);
        let whole = fs::read(&path).unwrap();

        for end in 0..=whole.len() {
            fs::write(&path, &whole[..end]).unwrap();
            let _ = read(&path);
        }
        for index in 0..whole.len() {
            for byte in [0u8, b'"', b'{', b'\n', 0xff] {
                let mut corrupt = whole.clone();
                corrupt[index] = byte;
                fs::write(&path, &corrupt).unwrap();
                let _ = read(&path);
            }
        }
    }

    #[test]
    fn a_damaged_journal_never_yields_a_patch_that_was_not_written_whole() {
        // The stronger half of the fuzz: whatever survives truncation must be a
        // prefix of what was recorded. Recovery that invents an edit is worse
        // than recovery that loses one.
        let dir = TempDir::new("journal-prefix");
        let script = dir.path().join("x.fountain");
        let mut journal =
            Journal::create(dir.path(), &script_id(&script), &script, "base").unwrap();
        let texts = ["one", "two", "three", "four"];
        for text in texts {
            journal.append(&change(1, text)).unwrap();
        }
        let path = journal.path().to_path_buf();
        drop(journal);
        let whole = fs::read(&path).unwrap();

        for end in 0..=whole.len() {
            fs::write(&path, &whole[..end]).unwrap();
            let Ok(recovery) = read(&path) else { continue };
            for (index, patch) in recovery.patches.iter().enumerate() {
                assert_eq!(patch.changed[0].text, texts[index], "at {end} bytes");
            }
        }
    }

    #[test]
    fn a_script_id_is_stable_and_distinguishes_paths() {
        let one = script_id(Path::new("/home/writer/heat.fountain"));
        assert_eq!(one, script_id(Path::new("/home/writer/heat.fountain")));
        assert_ne!(one, script_id(Path::new("/home/writer/heat2.fountain")));
        assert_eq!(one.len(), 16);
    }

    #[test]
    fn a_checksum_notices_a_change_of_length_and_a_change_of_content() {
        assert_ne!(checksum("abc"), checksum("abcd"));
        assert_ne!(checksum("abc"), checksum("abd"));
        assert_eq!(checksum("abc"), checksum("abc"));
    }
}
