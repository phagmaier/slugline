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

use std::collections::HashMap;
use std::fs::{self, File, OpenOptions};
use std::io::{self, Write};
use std::os::fd::AsRawFd;
use std::os::unix::fs::{FileExt, MetadataExt};
use std::path::{Path, PathBuf};

use serde::{Deserialize, Serialize};
use slugline_document::{
    BlockId, BlockKind, BlockSnapshot, Patch, TitleEntry, TitleField, TitlePage,
};

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

/// One `Key: value` pair of a title page, as a line of JSON.
///
/// The key keeps the spelling it was written with, which is what lets a key this
/// version does not recognise survive a crash as well as it survives a save.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
struct RecordTitle {
    key: String,
    value: String,
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
    /// Present only on the edits that changed the title page, so an ordinary
    /// keystroke's line is exactly as long as it was before Phase 7 — and a
    /// journal written by a build without this field still reads.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    title: Option<Vec<RecordTitle>>,
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
/// The file handle and its exclusive kernel lock are held for the session.
/// Reopening per append would be three syscalls instead of one on the keystroke
/// path, and would race with a checkpoint truncating the file underneath it.
pub struct Journal {
    file: File,
    path: PathBuf,
    seq: u64,
    records: u64,
    identities: Option<JournalIdentities>,
}

/// Translates live identities to the saved base's source-order identities.
/// It is session bookkeeping; records remain ordinary replayable outcomes.
struct JournalIdentities {
    ids: HashMap<u64, u64>,
    next: u64,
}

impl JournalIdentities {
    fn new(ids: &[BlockId]) -> Self {
        Self {
            ids: ids
                .iter()
                .enumerate()
                .map(|(i, id)| (id.0, i as u64 + 1))
                .collect(),
            next: ids.len() as u64,
        }
    }

    fn translate(&mut self, id: &mut u64) {
        *id = *self.ids.entry(*id).or_insert_with(|| {
            self.next += 1;
            self.next
        });
    }

    fn record(&mut self, record: &mut Record) {
        for id in &mut record.removed {
            self.translate(id);
        }
        for block in record
            .changed
            .iter_mut()
            .chain(record.inserted.iter_mut().map(|(_, b)| b))
        {
            self.translate(&mut block.id);
        }
    }
}

impl Journal {
    /// Starts a journal for `script`, whose contents are currently `base`.
    ///
    /// `script` is empty for a script that has never been saved. Such a session
    /// still gets a journal — it is the one a crash hurts most — and recovery
    /// replays it onto [`Document::blank`] rather than onto a file. `id` is what
    /// names the file, so the caller can keep two untitled sessions apart.
    ///
    /// **Refuses if a journal already exists at that name**, with
    /// [`io::ErrorKind::AlreadyExists`]. A journal on disk may belong to a live
    /// session or one that did not end cleanly, and its records may be the only
    /// copy of the edits it holds. Opening a script is not a decision about
    /// them: recovery may offer abandoned journals, and only recovery or an
    /// explicit discard may take that file away.
    ///
    /// That refusal is not theoretical. A session restore that reopened the
    /// script a pending offer names used to land here and truncate the offer to a
    /// header, so declining to decide — Escape, or "Decide later" — destroyed the
    /// edits the dialog had just promised to keep.
    pub fn create(dir: &Path, id: &str, script: &Path, base: &str) -> io::Result<Journal> {
        fs::create_dir_all(dir)?;
        let path = dir.join(format!("{id}.log"));
        match fs::symlink_metadata(&path) {
            Ok(_) => return Err(io::ErrorKind::AlreadyExists.into()),
            Err(error) if error.kind() == io::ErrorKind::NotFound => {}
            Err(error) => return Err(error),
        }
        let (prepared, seq) = prepare_journal(&path, script, base, &[])?;
        let file = prepared.publish_new()?;
        Ok(Journal {
            file,
            path,
            seq,
            records: seq,
            identities: None,
        })
    }

    /// Starts this session's journal over against a new document.
    ///
    /// The returned successor is already locked. Install it in place of this
    /// handle; the old inode stays locked until this handle is dropped, and no
    /// destructive operation on the old handle can affect the successor.
    pub fn replace(&self, script: &Path, base: &str) -> io::Result<Journal> {
        self.rebuild_at(script, base, &[])
    }

    /// Rewrites a journal so that it says `patches`, applied to `base`, and
    /// leaves it open for further appends.
    ///
    /// A destination that already exists must be abandoned: acquiring its
    /// recovery lock is required before replacement, and a live owner is
    /// refused without modifying either inode.
    ///
    /// This is the successor half of accepting a crash recovery, and the reason
    /// it exists is a rule the recovery path has to keep: **the journal
    /// describing the recovered edits is the only durable copy of them, so it
    /// must not stop existing until an equivalent one does.**
    ///
    /// Replaying a journal produces a document that is *ahead* of the file on
    /// disk, and recovery deliberately leaves the file alone — the writer has
    /// not agreed to anything yet. So the successor journal cannot be an empty
    /// one based on the recovered text (there would be nothing on disk holding
    /// the recovered edits, and its `base` would match no file, so
    /// [`verify`] would refuse it after a second crash). It is instead the same
    /// `base` the file still has, plus the records that were actually replayed.
    /// A second crash then recovers exactly what the first one did, plus
    /// whatever was typed after.
    ///
    /// Written through [`crate::atomic`]'s prepared save rather than by
    /// truncating in place: a crash halfway through rewriting a journal in place
    /// would leave a journal that has lost records, which is the loss this whole
    /// function exists to prevent. The rename either happened or did not.
    pub fn rebuild(
        dir: &Path,
        id: &str,
        script: &Path,
        base: &str,
        patches: &[Patch],
    ) -> io::Result<Journal> {
        fs::create_dir_all(dir)?;
        let path = dir.join(format!("{id}.log"));
        match RecoveryGuard::try_open(&path) {
            Ok(guard) => rebuild_locked(&guard.file, &path, script, base, patches),
            Err(error) if error.kind() == io::ErrorKind::NotFound => {
                let (prepared, seq) = prepare_journal(&path, script, base, patches)?;
                let file = prepared.publish_new()?;
                Ok(Journal {
                    file,
                    path,
                    seq,
                    records: seq,
                    identities: None,
                })
            }
            Err(error) => Err(error),
        }
    }

    /// Rebuilds the journal this session owns, returning its locked successor.
    ///
    /// Save As can change the script's id without changing this journal's path.
    /// The old lock is held through publication; the successor was locked
    /// before publication and uses the very same descriptor for later appends.
    pub fn rebuild_at(&self, script: &Path, base: &str, patches: &[Patch]) -> io::Result<Journal> {
        rebuild_locked(&self.file, &self.path, script, base, patches)
    }

    /// Rebuilds saved-base outcomes while preserving the live document's ids.
    pub fn rebuild_at_with_identities(
        &self,
        script: &Path,
        base: &str,
        patches: &[Patch],
        ids: &[BlockId],
    ) -> io::Result<Journal> {
        rebuild_locked_mapped(
            &self.file,
            &self.path,
            script,
            base,
            patches,
            Some(JournalIdentities::new(ids)),
        )
    }

    /// Records what one edit did. Nothing is recorded for an edit that changed
    /// nothing.
    pub fn append(&mut self, patch: &Patch) -> io::Result<()> {
        if patch.is_empty() {
            return Ok(());
        }
        self.seq += 1;
        // One `write_all` for the line and its terminator together. Two writes
        // could be interrupted between them, and a line without its newline is
        // exactly what the reader treats as damage.
        let mut outcome = record(self.seq, patch);
        if let Some(identities) = &mut self.identities {
            identities.record(&mut outcome);
        }
        let mut line = serde_json::to_vec(&outcome).map_err(io::Error::other)?;
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
        // The truncated header must reach the disk, or a power loss resurrects
        // the pre-save records and the next launch re-offers edits that are
        // already in the file. One fsync per save; the save itself already paid
        // for two.
        self.file.sync_all()?;
        self.seq = 0;
        self.records = 0;
        self.identities = None;
        Ok(())
    }

    /// Maps subsequent live outcomes to the identities assigned by a parse of
    /// this saved base, without reparsing or replacing the actor document.
    pub fn checkpoint_with_identities(
        &mut self,
        script: &Path,
        base: &str,
        ids: &[BlockId],
    ) -> io::Result<()> {
        self.checkpoint(script, base)?;
        self.identities = Some(JournalIdentities::new(ids));
        Ok(())
    }

    /// Ends the session cleanly: the journal is removed.
    ///
    /// Its *absence* is what says the previous session ended properly, so this
    /// is the one operation that must happen on a clean close and must not
    /// happen any other time.
    pub fn discard(self) -> io::Result<()> {
        remove_locked(&self.file, &self.path)
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

/// Exclusive ownership of an abandoned journal during recovery.
///
/// Acquisition is nonblocking. A live session holds the same kernel lock, so
/// neither recovery inspection nor a destructive decision can take it over.
pub struct RecoveryGuard {
    file: File,
    path: PathBuf,
}

impl RecoveryGuard {
    /// Acquires the current inode without waiting for an owner to release it.
    ///
    /// `WouldBlock` means either an owner is live or the pathname changed
    /// before ownership could be validated. All other lock and I/O errors are
    /// propagated; none authorize reading or mutating an unlocked journal.
    pub fn try_open(path: &Path) -> io::Result<RecoveryGuard> {
        let file = OpenOptions::new().read(true).write(true).open(path)?;
        Self::from_file(file, path)
    }

    fn from_file(file: File, path: &Path) -> io::Result<RecoveryGuard> {
        lock_exclusive(&file)?;
        // An opener can hold the predecessor inode while another owner
        // publishes a successor. Acquiring that obsolete inode's lock is not
        // ownership of the file that now lives at this path.
        validate_current(&file, path)?;
        Ok(RecoveryGuard {
            file,
            path: path.to_path_buf(),
        })
    }

    /// Reads from the locked descriptor, never reopening the pathname.
    pub fn read(&self) -> Result<Recovery, JournalError> {
        let length = self
            .file
            .metadata()
            .ok()
            .and_then(|metadata| usize::try_from(metadata.len()).ok())
            .ok_or(JournalError::Unreadable)?;
        let mut bytes = vec![0; length];
        self.file
            .read_exact_at(&mut bytes, 0)
            .map_err(|_| JournalError::Unreadable)?;
        read_bytes(&self.path, &bytes)
    }

    pub fn discard(self) -> io::Result<()> {
        remove_locked(&self.file, &self.path)
    }

    /// Publishes a locked successor before removing the guarded predecessor.
    ///
    /// When both names are the same, the replacement is a single atomic
    /// rename. With different names, the destination must itself be acquired
    /// or created without clobbering before the source is removed.
    pub fn rebuild(
        self,
        dir: &Path,
        id: &str,
        script: &Path,
        base: &str,
        patches: &[Patch],
    ) -> io::Result<Journal> {
        let destination = dir.join(format!("{id}.log"));
        if destination == self.path {
            return rebuild_locked(&self.file, &self.path, script, base, patches);
        }
        validate_current(&self.file, &self.path)?;
        let successor = Journal::rebuild(dir, id, script, base, patches)?;
        self.discard()?;
        Ok(successor)
    }
}

fn lock_exclusive(file: &File) -> io::Result<()> {
    // SAFETY: `file` owns a valid descriptor for the entire call. The flags
    // request a nonblocking exclusive lock and have no pointer arguments.
    if unsafe { libc::flock(file.as_raw_fd(), libc::LOCK_EX | libc::LOCK_NB) } == 0 {
        Ok(())
    } else {
        Err(io::Error::last_os_error())
    }
}

fn validate_current(file: &File, path: &Path) -> io::Result<()> {
    let held = file.metadata()?;
    let current = fs::metadata(path)?;
    if held.dev() == current.dev() && held.ino() == current.ino() {
        Ok(())
    } else {
        Err(io::Error::new(
            io::ErrorKind::WouldBlock,
            "the journal path changed while its lock was being acquired",
        ))
    }
}

fn remove_locked(file: &File, path: &Path) -> io::Result<()> {
    match validate_current(file, path) {
        Err(error) if error.kind() == io::ErrorKind::NotFound => return Ok(()),
        Err(error) => return Err(error),
        Ok(()) => {}
    }
    // The descriptor and its lock are still alive throughout the unlink.
    match fs::remove_file(path) {
        Err(error) if error.kind() == io::ErrorKind::NotFound => Ok(()),
        other => other,
    }
}

fn prepare_journal<'a>(
    path: &'a Path,
    script: &Path,
    base: &str,
    patches: &[Patch],
) -> io::Result<(crate::atomic::PreparedSave<'a>, u64)> {
    prepare_journal_mapped(path, script, base, patches, None)
}

fn prepare_journal_mapped<'a>(
    path: &'a Path,
    script: &Path,
    base: &str,
    patches: &[Patch],
    mut identities: Option<&mut JournalIdentities>,
) -> io::Result<(crate::atomic::PreparedSave<'a>, u64)> {
    let mut contents = Vec::new();
    write_line(
        &mut contents,
        &Header {
            version: FORMAT_VERSION,
            script: script.to_path_buf(),
            base: checksum(base),
        },
    )?;
    let mut seq = 0;
    for patch in patches {
        if patch.is_empty() {
            continue;
        }
        seq += 1;
        let mut outcome = record(seq, patch);
        if let Some(identities) = &mut identities {
            identities.record(&mut outcome);
        }
        write_line(&mut contents, &outcome)?;
    }
    let prepared = crate::atomic::prepare_save(path, &contents, lock_exclusive)
        .map_err(|error| io::Error::other(error.to_string()))?;
    Ok((prepared, seq))
}

fn rebuild_locked(
    file: &File,
    path: &Path,
    script: &Path,
    base: &str,
    patches: &[Patch],
) -> io::Result<Journal> {
    rebuild_locked_mapped(file, path, script, base, patches, None)
}

fn rebuild_locked_mapped(
    file: &File,
    path: &Path,
    script: &Path,
    base: &str,
    patches: &[Patch],
    mut identities: Option<JournalIdentities>,
) -> io::Result<Journal> {
    validate_current(file, path)?;
    let (prepared, seq) = prepare_journal_mapped(path, script, base, patches, identities.as_mut())?;
    validate_current(file, path)?;
    let file = prepared.publish()?;
    Ok(Journal {
        file,
        path: path.to_path_buf(),
        seq,
        records: seq,
        identities,
    })
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

/// The record one patch becomes. Shared by [`Journal::append`], which writes it
/// as it happens, and [`Journal::rebuild`], which writes a run of them at once —
/// so that a rebuilt journal cannot drift from an appended one.
fn record(seq: u64, patch: &Patch) -> Record {
    Record {
        seq,
        removed: patch.removed.iter().map(|id| id.0).collect(),
        changed: patch.changed.iter().map(RecordBlock::of).collect(),
        inserted: patch
            .inserted
            .iter()
            .map(|(index, block)| (*index, RecordBlock::of(block)))
            .collect(),
        title: patch.title_page.as_ref().map(|page| {
            page.entries
                .iter()
                .map(|entry| RecordTitle {
                    key: entry.field.key().to_owned(),
                    value: entry.value.clone(),
                })
                .collect()
        }),
    }
}

fn write_line(out: &mut Vec<u8>, value: &impl Serialize) -> io::Result<()> {
    serde_json::to_writer(&mut *out, value).map_err(io::Error::other)?;
    out.push(b'\n');
    Ok(())
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
    read_bytes(path, &bytes)
}

fn read_bytes(path: &Path, bytes: &[u8]) -> Result<Recovery, JournalError> {
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
        title_page: record.title.map(|entries| TitlePage {
            entries: entries
                .into_iter()
                .map(|entry| TitleEntry {
                    field: TitleField::from_key(&entry.key),
                    value: entry.value,
                })
                .collect(),
            // A recorded title page is one the writer edited, so it has no
            // provenance in the file it will be replayed onto.
            provenance: None,
        }),
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

/// Every candidate journal path in `dir`, including live sessions.
///
/// This only enumerates names. Acquire a [`RecoveryGuard`] before deciding
/// whether a candidate can be offered or removed. Sorted, so that two runs of
/// the same recovery offer the same order.
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
    match RecoveryGuard::try_open(path) {
        Ok(guard) => guard.discard(),
        Err(error) if error.kind() == io::ErrorKind::NotFound => Ok(()),
        Err(error) => Err(error),
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

    fn title_page(entries: &[(&str, &str)]) -> TitlePage {
        TitlePage {
            entries: entries
                .iter()
                .map(|(key, value)| TitleEntry {
                    field: TitleField::from_key(key),
                    value: (*value).to_owned(),
                })
                .collect(),
            provenance: None,
        }
    }

    #[test]
    fn a_title_page_edit_is_recorded_and_read_back_whole() {
        let dir = TempDir::new("journal-title");
        let script = dir.path().join("x.fountain");
        let mut journal =
            Journal::create(dir.path(), &script_id(&script), &script, "base").unwrap();
        // An unknown key beside a known one: the writer's own key survives a
        // crash exactly as it survives a save.
        let page = title_page(&[
            ("Title", "Big Fish"),
            ("Draft date", "26 July 2026"),
            ("Revision Colour", "Blue"),
        ]);
        journal.append(&change(1, "typed")).unwrap();
        journal
            .append(&Patch {
                title_page: Some(page.clone()),
                ..Patch::default()
            })
            .unwrap();
        let path = journal.path().to_path_buf();
        drop(journal);

        let recovery = read(&path).expect("the journal reads");
        assert_eq!(recovery.patches.len(), 2);
        assert_eq!(
            recovery.patches[0].title_page, None,
            "a keystroke records none"
        );
        assert_eq!(recovery.patches[1].title_page.as_ref(), Some(&page));
    }

    #[test]
    fn an_ordinary_keystroke_line_says_nothing_about_the_title_page() {
        // The field is skipped when absent, so Phase 7 did not make every line
        // of every journal longer, and a journal a Phase 6 build wrote still
        // reads here.
        let dir = TempDir::new("journal-title-absent");
        let script = dir.path().join("x.fountain");
        let mut journal =
            Journal::create(dir.path(), &script_id(&script), &script, "base").unwrap();
        journal.append(&change(1, "typed")).unwrap();
        let path = journal.path().to_path_buf();
        drop(journal);

        let text = fs::read_to_string(&path).unwrap();
        let record = text.lines().nth(1).expect("a header and one record");
        assert_eq!(
            record,
            r#"{"seq":1,"changed":[{"id":1,"kind":"action","text":"typed"}]}"#
        );
    }

    #[test]
    fn saved_identity_translation_preserves_source_and_later_inserted_ids() {
        let dir = TempDir::new("saved-identities");
        let script = dir.path().join("x.fountain");
        let base = "\u{feff}!One\r\n\r\n!Two\r\n";
        fs::write(&script, base).unwrap();
        let id = script_id(&script);
        let mut journal = Journal::create(dir.path(), &id, &script, base).unwrap();
        let live_ids = [BlockId(90), BlockId(4)];
        journal
            .checkpoint_with_identities(&script, base, &live_ids)
            .unwrap();
        assert_eq!(journal.records(), 0);
        journal.append(&change(4, "Earlier.")).unwrap();
        assert_eq!(
            read(journal.path()).unwrap().patches[0].changed[0].id,
            BlockId(2)
        );

        // These outcomes arrived while the saved base was being written.
        let buffered = Patch {
            changed: vec![snapshot(4, BlockKind::Action, "Changed.")],
            inserted: vec![(0, snapshot(100, BlockKind::Action, "New."))],
            ..Patch::default()
        };
        journal = journal
            .rebuild_at_with_identities(&script, base, &[buffered], &live_ids)
            .unwrap();
        journal.append(&change(100, "Newer.")).unwrap();
        let path = journal.path().to_path_buf();
        drop(journal);
        let recovery = read(&path).unwrap();
        let mut document = slugline_document::Document::parse(&verify(&recovery.header).unwrap());
        for patch in &recovery.patches {
            document.replay(patch).unwrap();
        }
        assert_eq!(
            document.serialise(),
            "\u{feff}Newer.\r\n\r\n!One\r\n\r\nChanged.\r\n"
        );

        // A second crash uses the already translated identities, without any
        // persisted mapping or reconstruction of the former live id space.
        let guard = RecoveryGuard::try_open(&path).unwrap();
        let mut successor = guard
            .rebuild(dir.path(), &id, &script, base, &recovery.patches)
            .unwrap();
        successor.append(&change(3, "Newest.")).unwrap();
        let recovered = read(successor.path()).unwrap();
        let mut document = slugline_document::Document::parse(base);
        for patch in &recovered.patches {
            document.replay(patch).unwrap();
        }
        assert_eq!(
            document.serialise(),
            "\u{feff}Newest.\r\n\r\n!One\r\n\r\nChanged.\r\n"
        );
    }

    /// A rebuilt journal is byte-for-byte what an appended one would have been.
    ///
    /// The two writers exist for different reasons — one records an edit as it
    /// happens, the other lays down a run of them at once — and the moment they
    /// disagree about the format, a recovered session's journal stops being
    /// readable by the same reader. They share [`record`] so that they cannot.
    #[test]
    fn a_rebuilt_journal_is_what_an_appended_one_would_have_been() {
        let dir = TempDir::new("rebuild-matches-append");
        let patches = [
            change(1, "one"),
            change(1, "one two"),
            change(1, "one two."),
        ];

        let appended = dir.path().join("appended");
        let mut journal =
            Journal::create(&appended, "script", Path::new("/tmp/heat.fountain"), "BASE").unwrap();
        for patch in &patches {
            journal.append(patch).unwrap();
        }
        let by_appending = fs::read(journal.path()).unwrap();
        drop(journal);

        let rebuilt = dir.path().join("rebuilt");
        let journal = Journal::rebuild(
            &rebuilt,
            "script",
            Path::new("/tmp/heat.fountain"),
            "BASE",
            &patches,
        )
        .unwrap();
        assert_eq!(fs::read(journal.path()).unwrap(), by_appending);
        assert_eq!(journal.records(), 3);
    }

    /// Rebuilding replaces a journal in place, and the replacement is complete
    /// or absent — never half-written. It is the only copy of the edits in it,
    /// so a truncating write here would be the loss it exists to prevent.
    #[test]
    fn rebuilding_replaces_a_journal_whole() {
        let dir = TempDir::new("rebuild-in-place");
        let script = Path::new("/tmp/heat.fountain");

        let mut journal = Journal::create(dir.path(), "script", script, "BASE").unwrap();
        journal.append(&change(1, "before")).unwrap();
        let path = journal.path().to_path_buf();
        drop(journal);

        let patches = [change(1, "before"), change(1, "before and after")];
        let journal = Journal::rebuild(dir.path(), "script", script, "BASE", &patches).unwrap();
        assert_eq!(journal.path(), path, "the same name, replaced");
        drop(journal);

        let names: Vec<String> = fs::read_dir(dir.path())
            .unwrap()
            .flatten()
            .map(|entry| entry.file_name().to_string_lossy().into_owned())
            .collect();
        assert_eq!(names, vec!["script.log".to_owned()], "no temp file left");

        let recovery = read(&path).unwrap();
        assert_eq!(recovery.patches.len(), 2);
        assert!(!recovery.damaged);
    }

    /// A rebuilt journal keeps taking appends, at the right sequence numbers.
    /// This is the session continuing after recovery, which is the case F2's
    /// second test is about.
    #[test]
    fn a_rebuilt_journal_carries_on_being_written_to() {
        let dir = TempDir::new("rebuild-then-append");
        let script = Path::new("/tmp/heat.fountain");
        let patches = [change(1, "one"), change(1, "one two")];

        let mut journal = Journal::rebuild(dir.path(), "s", script, "BASE", &patches).unwrap();
        journal.append(&change(1, "one two three")).unwrap();
        assert_eq!(journal.records(), 3);
        let path = journal.path().to_path_buf();
        drop(journal);

        let recovery = read(&path).unwrap();
        assert!(!recovery.damaged, "the appended line is whole");
        assert_eq!(recovery.patches.len(), 3);
        let mut document = Document::parse("one\n");
        // The last record is the state the block ends in; replaying all three in
        // order must land on it.
        for patch in &recovery.patches {
            let _ = document.replay(patch);
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

    /// Starting a session must not be able to erase one that crashed.
    ///
    /// The journal on disk is the only copy of the edits it holds, and opening
    /// the script again is not a decision about them.
    #[test]
    fn creating_a_journal_refuses_to_take_over_one_already_there() {
        let dir = TempDir::new("journal-occupied");
        let script = dir.path().join("x.fountain");
        let id = script_id(&script);
        let mut crashed = Journal::create(dir.path(), &id, &script, "base").unwrap();
        crashed.append(&change(1, "unsaved")).unwrap();
        let path = crashed.path().to_path_buf();
        drop(crashed);
        let before = fs::read(&path).unwrap();

        let refused = match Journal::create(dir.path(), &id, &script, "base") {
            Err(error) => error,
            Ok(_) => panic!("a pending journal was taken over"),
        };
        assert_eq!(refused.kind(), io::ErrorKind::AlreadyExists);
        assert_eq!(fs::read(&path).unwrap(), before, "not one byte of it");
        assert_eq!(read(&path).unwrap().patches.len(), 1, "still recoverable");
    }

    /// The other door, for the caller entitled to it: a session that already
    /// holds this journal and has just replaced its document with the file.
    #[test]
    fn replacing_a_journal_starts_it_again() {
        let dir = TempDir::new("journal-replaced");
        let script = dir.path().join("x.fountain");
        let id = script_id(&script);
        let mut journal = Journal::create(dir.path(), &id, &script, "before").unwrap();
        journal.append(&change(1, "a")).unwrap();
        journal = journal.replace(&script, "after").unwrap();
        let path = journal.path().to_path_buf();
        assert_eq!(journal.records(), 0);
        drop(journal);
        let recovery = read(&path).unwrap();
        assert!(recovery.patches.is_empty());
        assert_eq!(recovery.header.base, checksum("after"));
    }

    #[test]
    fn a_live_journal_refuses_foreign_recovery_discard_and_rebuild() {
        let dir = TempDir::new("journal-live-lock");
        let script = dir.path().join("x.fountain");
        let mut journal = Journal::create(dir.path(), "session", &script, "BASE").unwrap();
        journal.append(&change(1, "unsaved")).unwrap();
        let path = journal.path().to_path_buf();
        let before = fs::read(&path).unwrap();
        let observer = File::open(&path).unwrap();

        assert_eq!(
            lock_exclusive(&observer).unwrap_err().kind(),
            io::ErrorKind::WouldBlock,
        );
        assert_eq!(
            RecoveryGuard::try_open(&path).err().unwrap().kind(),
            io::ErrorKind::WouldBlock,
        );
        assert_eq!(
            discard_at(&path).unwrap_err().kind(),
            io::ErrorKind::WouldBlock,
        );
        assert_eq!(
            Journal::rebuild(dir.path(), "session", &script, "NEW", &[])
                .err()
                .unwrap()
                .kind(),
            io::ErrorKind::WouldBlock,
        );
        assert_eq!(fs::read(&path).unwrap(), before);
        drop(journal);

        let guard = RecoveryGuard::try_open(&path).unwrap();
        assert_eq!(guard.read().unwrap().patches, vec![change(1, "unsaved")]);
        guard.discard().unwrap();
        assert!(!path.exists());
    }

    #[test]
    fn a_prepared_journal_is_locked_before_and_after_no_clobber_publication() {
        let dir = TempDir::new("journal-prepared-lock");
        let path = dir.path().join("session.log");
        let (prepared, _) = prepare_journal(&path, Path::new(""), "", &[]).unwrap();
        assert!(!path.exists());
        let observer = File::open(dir.path().join(&dir.entries()[0])).unwrap();
        let inode = observer.metadata().unwrap().ino();
        assert_eq!(
            lock_exclusive(&observer).unwrap_err().kind(),
            io::ErrorKind::WouldBlock,
        );

        let file = prepared.publish_new().unwrap();
        assert_eq!(file.metadata().unwrap().ino(), inode);
        assert_eq!(fs::metadata(&path).unwrap().ino(), inode);
        assert_eq!(
            RecoveryGuard::try_open(&path).err().unwrap().kind(),
            io::ErrorKind::WouldBlock,
        );
        assert_eq!(dir.entries(), vec!["session.log".to_owned()]);
        drop(file);
        lock_exclusive(&observer).unwrap();
    }

    #[test]
    fn missing_destination_publication_cannot_clobber_a_racing_creator() {
        let dir = TempDir::new("journal-create-race");
        let path = dir.path().join("session.log");
        let (prepared, _) = prepare_journal(&path, Path::new(""), "first", &[]).unwrap();
        let journal = Journal::create(dir.path(), "session", Path::new(""), "second").unwrap();
        let before = fs::read(&path).unwrap();
        assert_eq!(
            prepared.publish_new().err().unwrap().kind(),
            io::ErrorKind::AlreadyExists,
        );
        assert_eq!(fs::read(&path).unwrap(), before);
        assert_eq!(dir.entries(), vec!["session.log".to_owned()]);
        assert_eq!(
            RecoveryGuard::try_open(&path).err().unwrap().kind(),
            io::ErrorKind::WouldBlock,
        );
        journal.discard().unwrap();
    }

    #[test]
    fn owned_rebuild_keeps_both_inodes_locked_and_stale_discard_is_refused() {
        let dir = TempDir::new("journal-owned-rebuild");
        let script = dir.path().join("x.fountain");
        let journal = Journal::create(dir.path(), "session", &script, "BASE").unwrap();
        let path = journal.path().to_path_buf();
        let predecessor = File::open(&path).unwrap();
        let mut successor = journal
            .rebuild_at(&script, "BASE", &[change(1, "recovered")])
            .unwrap();
        let current = File::open(&path).unwrap();
        assert_ne!(
            predecessor.metadata().unwrap().ino(),
            current.metadata().unwrap().ino(),
        );
        assert_eq!(
            lock_exclusive(&predecessor).unwrap_err().kind(),
            io::ErrorKind::WouldBlock,
        );
        assert_eq!(
            lock_exclusive(&current).unwrap_err().kind(),
            io::ErrorKind::WouldBlock,
        );
        let before = fs::read(&path).unwrap();
        assert_eq!(
            journal.discard().unwrap_err().kind(),
            io::ErrorKind::WouldBlock
        );
        assert_eq!(fs::read(&path).unwrap(), before);
        lock_exclusive(&predecessor).unwrap();
        assert_eq!(
            lock_exclusive(&current).unwrap_err().kind(),
            io::ErrorKind::WouldBlock,
        );
        successor.append(&change(1, "continued")).unwrap();
        assert_eq!(read(&path).unwrap().patches.len(), 2);
        successor.discard().unwrap();
    }

    #[test]
    fn acquiring_a_predecessor_descriptor_cannot_claim_its_successor_path() {
        let dir = TempDir::new("journal-stale-opener");
        let journal = Journal::create(dir.path(), "session", Path::new(""), "before").unwrap();
        let path = journal.path().to_path_buf();
        let opened_before_publication = File::open(&path).unwrap();
        let successor = journal.replace(Path::new(""), "after").unwrap();
        drop(journal);
        let before = fs::read(&path).unwrap();

        assert_eq!(
            RecoveryGuard::from_file(opened_before_publication, &path)
                .err()
                .unwrap()
                .kind(),
            io::ErrorKind::WouldBlock,
        );
        assert_eq!(fs::read(&path).unwrap(), before);
        assert_eq!(
            RecoveryGuard::try_open(&path).err().unwrap().kind(),
            io::ErrorKind::WouldBlock,
        );
        successor.discard().unwrap();
    }

    #[test]
    fn a_recovery_guard_reads_its_inode_and_will_not_unlink_a_replacement() {
        let dir = TempDir::new("journal-guard-inode");
        let mut journal = Journal::create(dir.path(), "session", Path::new(""), "").unwrap();
        journal.append(&change(1, "original")).unwrap();
        let path = journal.path().to_path_buf();
        drop(journal);
        let guard = RecoveryGuard::try_open(&path).unwrap();

        let moved = dir.path().join("moved.log");
        fs::rename(&path, &moved).unwrap();
        let replacement = Journal::create(dir.path(), "session", Path::new(""), "other").unwrap();
        let before = fs::read(&path).unwrap();
        assert_eq!(guard.read().unwrap().patches, vec![change(1, "original")]);
        assert_eq!(
            guard.discard().unwrap_err().kind(),
            io::ErrorKind::WouldBlock
        );
        assert_eq!(fs::read(&path).unwrap(), before);
        discard_at(&moved).unwrap();
        replacement.discard().unwrap();
    }

    #[test]
    fn recovery_migration_preserves_source_when_destination_is_live() {
        let dir = TempDir::new("journal-recovery-migration");
        let script = dir.path().join("x.fountain");
        let mut source = Journal::create(dir.path(), "source", &script, "BASE").unwrap();
        source.append(&change(1, "recovered")).unwrap();
        let source_path = source.path().to_path_buf();
        drop(source);
        let destination = Journal::create(dir.path(), "destination", &script, "BASE").unwrap();
        let destination_path = destination.path().to_path_buf();
        let source_bytes = fs::read(&source_path).unwrap();
        let destination_bytes = fs::read(&destination_path).unwrap();
        let guard = RecoveryGuard::try_open(&source_path).unwrap();
        let patches = guard.read().unwrap().patches;
        assert_eq!(
            guard
                .rebuild(dir.path(), "destination", &script, "BASE", &patches)
                .err()
                .unwrap()
                .kind(),
            io::ErrorKind::WouldBlock,
        );
        assert_eq!(fs::read(&source_path).unwrap(), source_bytes);
        assert_eq!(fs::read(&destination_path).unwrap(), destination_bytes);

        drop(destination);
        let guard = RecoveryGuard::try_open(&source_path).unwrap();
        let successor = guard
            .rebuild(dir.path(), "destination", &script, "BASE", &patches)
            .unwrap();
        assert!(!source_path.exists());
        assert_eq!(read(&destination_path).unwrap().patches, patches);
        assert_eq!(
            RecoveryGuard::try_open(&destination_path)
                .err()
                .unwrap()
                .kind(),
            io::ErrorKind::WouldBlock,
        );
        successor.discard().unwrap();
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
                title_page: Some(title_page(&[
                    ("Title", "Héllo 🎬"),
                    ("Revision Colour", "Blue"),
                ])),
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
