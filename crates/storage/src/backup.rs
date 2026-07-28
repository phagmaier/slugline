//! Rolling backups: §Phase 4's "last N versions plus one per day for M days".
//!
//! A backup is a whole copy of the script, written beside nothing, in
//! `$XDG_STATE_HOME/slugline/backups/<script-id>/<unix-millis>.fountain`. Whole
//! copies rather than diffs because a diff chain is only as good as its weakest
//! link and this is the thing that exists for when something has gone wrong. A
//! feature-length script is half a megabyte; ten of them is five.
//!
//! The timestamp *is* the file name. There is no index, no manifest and no
//! database — the directory listing is the record, so a backup directory that
//! outlives every other piece of state is still fully usable, and so is one the
//! user copies somewhere else. The one extra file is `origin`, which holds the
//! path the backups came from, so that a directory named after a hash can still
//! say what it is. It goes through the same atomic save as the copies do — a
//! half-written path is provenance that lies, which is worse than provenance
//! that is missing — but failing to write it does not fail the backup. See
//! [`Written`].
//!
//! Retention keeps, in one pass: the newest `keep_versions` copies unconditionally,
//! plus the newest copy from each of the last `keep_days` UTC days. A day bucket
//! is `millis / 86_400_000`, which needs no calendar and no `chrono`.

use std::fs;
use std::path::{Path, PathBuf};
use std::time::{SystemTime, UNIX_EPOCH};

use crate::atomic::{save_atomically, SaveError};
use crate::journal::script_id;

const MILLIS_PER_DAY: u64 = 86_400_000;

/// How many copies to keep. §Phase 4's defaults are 10 and 7.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Retention {
    pub keep_versions: u32,
    pub keep_days: u32,
}

impl Default for Retention {
    fn default() -> Retention {
        Retention {
            keep_versions: 10,
            keep_days: 7,
        }
    }
}

/// One copy on disk.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Backup {
    pub path: PathBuf,
    /// When it was written, as Unix milliseconds. The UI formats it; this crate
    /// has no business deciding what a date looks like in someone's locale.
    pub written_millis: u64,
    pub bytes: u64,
}

impl Backup {
    fn day(&self) -> u64 {
        self.written_millis / MILLIS_PER_DAY
    }
}

/// What [`write`] managed to do.
///
/// Two things happen in one call and they can fail separately, so they are
/// reported separately. The copy is the point of the exercise; `origin` is the
/// label on the directory it went into, and a rescue copy without a label is
/// worth immeasurably more than no copy at all.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Written {
    /// The copy. Reaching this at all means it is on disk and whole; [`write`]
    /// returns an `Err` rather than a `Written` when it is not.
    pub backup: Backup,
    /// Whether the directory's `origin` file says what these copies came from.
    ///
    /// An `Err` is the explicit degraded result: the backup is good, and what
    /// the user has lost is the ability to tell what a directory named after a
    /// hash is a backup *of* once the library index — a cache — is gone. The
    /// next backup into the same directory tries again.
    pub origin: Result<(), SaveError>,
}

/// Where one script's copies live.
pub fn directory(root: &Path, script: &Path) -> PathBuf {
    root.join(script_id(script))
}

/// Writes a copy of `contents` and prunes what `retention` no longer wants.
///
/// Uses the same atomic save the script itself gets. A backup written by a
/// process that died halfway would be a file that looks like a rescue and is
/// not, which is worse than no backup at all.
pub fn write(
    root: &Path,
    script: &Path,
    contents: &str,
    retention: Retention,
) -> Result<Written, SaveError> {
    let directory = directory(root, script);
    if let Err(error) = fs::create_dir_all(&directory) {
        return Err(SaveError::Io {
            path: directory,
            message: error.to_string(),
        });
    }

    // Before the copy, so that a directory exists for as little time as
    // possible without saying what it is. Its failure is carried, not returned:
    // every reason the label cannot be written that would also cost us the copy
    // — a full disk, an unwritable directory — is about to be reported by the
    // save below, and the reasons that are left are reasons to keep the copy.
    let origin = record_origin(&directory, script);

    let written_millis = now_millis();
    let path = unique_path(&directory, written_millis);
    save_atomically(&path, contents)?;

    let backup = Backup {
        path,
        written_millis,
        bytes: contents.len() as u64,
    };
    // Pruning is best effort: the copy is written, and failing to delete an old
    // one is not a reason to tell the user the backup did not happen.
    let _ = prune(root, script, retention);
    Ok(Written { backup, origin })
}

/// Writes `origin` unless it already holds exactly the right path.
///
/// Atomically, like every other file this project owns: `origin` is small
/// enough that a torn write is unlikely and not so small that it is impossible,
/// and a truncated path is a directory claiming to be a backup of somewhere
/// nobody's script lives.
///
/// Rewriting whenever the contents differ is what repairs one a previous
/// version left truncated. It costs a small read per backup and never fires
/// spuriously: a directory's name is a hash of the path, so within one
/// directory that path does not change, and "differs" only ever means
/// "damaged".
fn record_origin(directory: &Path, script: &Path) -> Result<(), SaveError> {
    let path = directory.join("origin");
    let wanted = script.to_string_lossy();
    if fs::read(&path).is_ok_and(|found| found == wanted.as_bytes()) {
        return Ok(());
    }
    save_atomically(&path, wanted.as_bytes())
}

/// Two saves in the same millisecond would otherwise be the same file. The
/// second gets a suffix rather than overwriting the first.
fn unique_path(directory: &Path, millis: u64) -> PathBuf {
    let first = directory.join(format!("{millis}.fountain"));
    if !first.exists() {
        return first;
    }
    for nonce in 1..1000 {
        let candidate = directory.join(format!("{millis}-{nonce}.fountain"));
        if !candidate.exists() {
            return candidate;
        }
    }
    first
}

/// Every copy of one script, newest first.
pub fn list(root: &Path, script: &Path) -> Vec<Backup> {
    let mut backups: Vec<Backup> = fs::read_dir(directory(root, script))
        .into_iter()
        .flatten()
        .flatten()
        .filter_map(|entry| {
            let path = entry.path();
            let stem = path.file_stem()?.to_str()?;
            if path.extension()? != "fountain" {
                return None;
            }
            // `1731000000000` or `1731000000000-2`; anything else is not ours.
            let millis: u64 = stem.split('-').next()?.parse().ok()?;
            Some(Backup {
                written_millis: millis,
                bytes: entry.metadata().map(|meta| meta.len()).unwrap_or(0),
                path,
            })
        })
        .collect();
    backups.sort_by(|a, b| {
        b.written_millis
            .cmp(&a.written_millis)
            .then(b.path.cmp(&a.path))
    });
    backups
}

/// Deletes the copies `retention` does not call for. Returns how many went.
pub fn prune(root: &Path, script: &Path, retention: Retention) -> std::io::Result<usize> {
    let backups = list(root, script);
    let keep_versions = retention.keep_versions as usize;
    let today = now_millis() / MILLIS_PER_DAY;
    let oldest_day = today.saturating_sub(retention.keep_days.saturating_sub(1) as u64);

    let mut days_kept: Vec<u64> = Vec::new();
    let mut removed = 0;
    for (index, backup) in backups.iter().enumerate() {
        // The newest N, whatever day they are from: this is what makes "undo the
        // last five saves" possible on a day when the writer saved fifty times.
        if index < keep_versions {
            days_kept.push(backup.day());
            continue;
        }
        // Then one per day, so that last Tuesday's draft is still reachable
        // after a thousand saves since.
        let day = backup.day();
        if day >= oldest_day && !days_kept.contains(&day) {
            days_kept.push(day);
            continue;
        }
        if fs::remove_file(&backup.path).is_ok() {
            removed += 1;
        }
    }
    Ok(removed)
}

/// The script a backup directory came from, as recorded by [`write`].
pub fn origin(directory: &Path) -> Option<PathBuf> {
    let recorded = fs::read_to_string(directory.join("origin")).ok()?;
    let recorded = recorded.trim_end_matches('\n');
    // An empty file is what a non-atomic write could leave behind, and what a
    // pre-atomic version of this crate did leave behind. It is not a path, and
    // answering `Some("")` would be a worse answer than admitting we do not
    // know — the caller would go looking for a script at the root of nothing.
    if recorded.is_empty() {
        return None;
    }
    Some(PathBuf::from(recorded))
}

fn now_millis() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|since| since.as_millis() as u64)
        .unwrap_or(0)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::testing::TempDir;

    /// A copy written at an exact time, so retention can be tested without
    /// waiting seven days.
    fn plant(root: &Path, script: &Path, millis: u64, contents: &str) -> PathBuf {
        let directory = directory(root, script);
        fs::create_dir_all(&directory).unwrap();
        let path = directory.join(format!("{millis}.fountain"));
        fs::write(&path, contents).unwrap();
        path
    }

    #[test]
    fn a_backup_is_a_whole_readable_copy() {
        let dir = TempDir::new("backup-write");
        let script = Path::new("/home/writer/heat.fountain");
        let written = write(
            dir.path(),
            script,
            "INT. HOUSE - DAY\n",
            Retention::default(),
        )
        .expect("the backup is written");
        assert_eq!(
            fs::read_to_string(&written.backup.path).unwrap(),
            "INT. HOUSE - DAY\n"
        );
        assert_eq!(written.backup.bytes, 17);
    }

    #[test]
    fn a_backup_directory_says_what_it_is_a_backup_of() {
        let dir = TempDir::new("backup-origin");
        let script = Path::new("/home/writer/heat.fountain");
        let written = write(dir.path(), script, "text\n", Retention::default()).unwrap();
        assert_eq!(written.origin, Ok(()));
        assert_eq!(origin(&directory(dir.path(), script)), Some(script.into()));
    }

    #[test]
    fn the_origin_file_is_written_atomically_and_leaves_nothing_behind() {
        let dir = TempDir::new("backup-origin-atomic");
        let script = Path::new("/home/writer/heat.fountain");
        write(dir.path(), script, "text\n", Retention::default()).unwrap();

        // No `.tmp-` sibling from either write, and nothing but the copy and
        // its label.
        let directory = directory(dir.path(), script);
        let mut names: Vec<String> = fs::read_dir(&directory)
            .unwrap()
            .flatten()
            .map(|entry| entry.file_name().to_string_lossy().into_owned())
            .collect();
        names.sort();
        assert_eq!(names.len(), 2, "{names:?}");
        assert!(names.contains(&"origin".to_string()), "{names:?}");
        assert!(
            !names.iter().any(|name| crate::atomic::is_temp_file(name)),
            "{names:?}"
        );
    }

    #[test]
    fn an_origin_that_cannot_be_written_does_not_cost_the_backup() {
        let dir = TempDir::new("backup-origin-blocked");
        let script = Path::new("/home/writer/heat.fountain");
        // A directory where the file belongs: `rename(2)` will not put a file
        // over it, and no amount of privilege changes that, so this is the one
        // way to fail the label that also fails for root under CI.
        let directory = directory(dir.path(), script);
        fs::create_dir_all(directory.join("origin")).unwrap();

        let written = write(
            dir.path(),
            script,
            "INT. HOUSE - DAY\n",
            Retention::default(),
        )
        .expect("the copy is still written");
        assert!(
            written.origin.is_err(),
            "the degraded result has to be explicit"
        );
        assert_eq!(
            fs::read_to_string(&written.backup.path).unwrap(),
            "INT. HOUSE - DAY\n",
            "and the copy is whole"
        );
        assert_eq!(list(dir.path(), script).len(), 1);
        assert_eq!(origin(&directory), None, "with nothing to say what it is");
    }

    #[test]
    fn a_truncated_origin_is_repaired_by_the_next_backup() {
        let dir = TempDir::new("backup-origin-repair");
        let script = Path::new("/home/writer/heat.fountain");
        let directory = directory(dir.path(), script);
        fs::create_dir_all(&directory).unwrap();
        // What a torn `fs::write` leaves: the file exists, so the old code
        // would never have looked at it again.
        fs::write(directory.join("origin"), "/home/writ").unwrap();
        assert_eq!(origin(&directory), Some(PathBuf::from("/home/writ")));

        write(dir.path(), script, "text\n", Retention::default()).unwrap();
        assert_eq!(origin(&directory), Some(script.into()));
    }

    #[test]
    fn an_empty_origin_is_no_answer_rather_than_an_empty_path() {
        let dir = TempDir::new("backup-origin-empty");
        let directory = dir.path().join("somehash");
        fs::create_dir_all(&directory).unwrap();
        fs::write(directory.join("origin"), "").unwrap();
        assert_eq!(origin(&directory), None);
    }

    #[test]
    fn copies_come_back_newest_first() {
        let dir = TempDir::new("backup-order");
        let script = Path::new("/x.fountain");
        plant(dir.path(), script, 1_000, "old");
        plant(dir.path(), script, 3_000, "new");
        plant(dir.path(), script, 2_000, "middle");
        let listed = list(dir.path(), script);
        assert_eq!(
            listed.iter().map(|b| b.written_millis).collect::<Vec<_>>(),
            [3_000, 2_000, 1_000]
        );
    }

    #[test]
    fn two_saves_in_one_millisecond_are_two_files() {
        let dir = TempDir::new("backup-collision");
        let script = Path::new("/x.fountain");
        let directory = directory(dir.path(), script);
        fs::create_dir_all(&directory).unwrap();
        let first = unique_path(&directory, 5_000);
        fs::write(&first, "a").unwrap();
        let second = unique_path(&directory, 5_000);
        assert_ne!(first, second);
    }

    #[test]
    fn the_newest_versions_are_kept_whatever_day_they_are_from() {
        let dir = TempDir::new("backup-versions");
        let script = Path::new("/x.fountain");
        let today = now_millis() / MILLIS_PER_DAY * MILLIS_PER_DAY;
        // Twenty saves inside one hour, which is an ordinary afternoon.
        for step in 0..20 {
            plant(dir.path(), script, today + step * 60_000, "text");
        }
        prune(
            dir.path(),
            script,
            Retention {
                keep_versions: 10,
                keep_days: 7,
            },
        )
        .unwrap();
        assert_eq!(list(dir.path(), script).len(), 10);
    }

    #[test]
    fn one_copy_per_day_survives_a_busy_week() {
        let dir = TempDir::new("backup-days");
        let script = Path::new("/x.fountain");
        let today = now_millis() / MILLIS_PER_DAY;
        // One save a day for a fortnight, plus a burst today.
        for day in 0..14 {
            plant(
                dir.path(),
                script,
                (today - day) * MILLIS_PER_DAY + 3_600_000,
                "text",
            );
        }
        for minute in 1..20 {
            plant(
                dir.path(),
                script,
                today * MILLIS_PER_DAY + 7_200_000 + minute * 60_000,
                "text",
            );
        }

        prune(
            dir.path(),
            script,
            Retention {
                keep_versions: 10,
                keep_days: 7,
            },
        )
        .unwrap();
        let kept = list(dir.path(), script);
        let days: std::collections::HashSet<u64> = kept.iter().map(|b| b.day()).collect();
        // The last ten saves are all from today, so the daily rule is the only
        // thing keeping the six days before it — and it must have kept them.
        assert_eq!(kept.len(), 16, "ten versions plus six older days");
        assert_eq!(days.len(), 7);
        assert!(
            !days.contains(&(today - 7)),
            "a week and a day ago is outside the window"
        );
    }

    #[test]
    fn pruning_an_empty_directory_is_not_an_error() {
        let dir = TempDir::new("backup-nothing");
        assert_eq!(
            prune(dir.path(), Path::new("/x.fountain"), Retention::default()).unwrap(),
            0
        );
        assert!(list(dir.path(), Path::new("/x.fountain")).is_empty());
    }

    #[test]
    fn files_that_are_not_backups_are_ignored_rather_than_deleted() {
        let dir = TempDir::new("backup-strangers");
        let script = Path::new("/x.fountain");
        let directory = directory(dir.path(), script);
        fs::create_dir_all(&directory).unwrap();
        fs::write(directory.join("origin"), "/x.fountain").unwrap();
        fs::write(directory.join("notes.txt"), "hello").unwrap();
        plant(dir.path(), script, 1_000, "text");

        assert_eq!(list(dir.path(), script).len(), 1);
        prune(
            dir.path(),
            script,
            Retention {
                keep_versions: 0,
                keep_days: 0,
            },
        )
        .unwrap();
        assert!(directory.join("origin").exists());
        assert!(directory.join("notes.txt").exists());
    }
}
