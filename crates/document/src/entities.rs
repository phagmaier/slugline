//! Incremental screenplay entity index and completion ranking (§7).
//!
//! The index remembers the contribution of each block.  Updating a patch removes
//! only the old contribution for the affected ids and reads only their new
//! blocks; the edit hot path therefore never scans the document.

use std::collections::{BTreeMap, HashMap};

use crate::{split_scene_number, Block, BlockId, BlockKind, Document};

/// The §7 extensions, written as the letters they are made of.
///
/// The canonical spellings are `(V.O.)`, `(O.S.)`, `(O.C.)`, `(CONT'D)` and
/// `(SUBTITLE)`, and those are what a script displays. The keys drop the
/// punctuation because the punctuation is what writers drop: `(O.S)` and `(VO)`
/// are the same extension typed in a hurry, and matching the canonical spelling
/// literally made each of them a *separate character* in the index — a phantom
/// `BOB (O.S)` beside the real `BOB`. See ADR 0031.
const CHARACTER_EXTENSIONS: [&str; 5] = ["VO", "OS", "OC", "CONTD", "SUBTITLE"];
const TIMES: [&str; 8] = [
    "DAY",
    "NIGHT",
    "CONTINUOUS",
    "LATER",
    "MOMENTS LATER",
    "DAWN",
    "DUSK",
    "SAME",
];
const SCENE_PREFIXES: [&str; 6] = ["INT.", "EXT.", "INT./EXT.", "INT/EXT.", "I/E.", "EST."];

#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord, Hash)]
pub enum EntityKind {
    Character,
    Location,
    ScenePrefix,
    TimeOfDay,
    Transition,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Completion {
    pub kind: EntityKind,
    pub value: String,
    pub frequency: u32,
    pub recency: u64,
    pub pinned: bool,
}

/// The parts of a scene heading that navigation displays.
///
/// A forced scene heading is allowed to have no standard INT/EXT prefix. In
/// that case `prefix` is empty and the whole heading (apart from an optional
/// scene number and time of day) is the location.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SceneHeadingParts {
    pub prefix: String,
    pub location: String,
    pub time_of_day: Option<String>,
    pub scene_number: Option<String>,
}

/// One character in the navigator, derived from the entity index.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct NavigatorCharacter {
    pub name: String,
    pub frequency: u32,
    pub blocks: Vec<BlockId>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
struct Contribution {
    kind: EntityKind,
    key: String,
    display: String,
}

#[derive(Debug, Clone, Default)]
struct Aggregate {
    displays: BTreeMap<String, u32>,
    frequency: u32,
    recency: u64,
}

#[derive(Debug, Clone, Default)]
pub struct EntityIndex {
    by_block: HashMap<BlockId, Vec<Contribution>>,
    entities: BTreeMap<(EntityKind, String), Aggregate>,
    pinned: BTreeMap<(EntityKind, String), String>,
    clock: u64,
}

impl EntityIndex {
    /// The only full scan: once, when a document becomes a session.
    pub fn build(document: &Document) -> EntityIndex {
        let mut index = EntityIndex::default();
        for block in document.blocks() {
            index.replace(block.id(), Some(block));
        }
        index
    }

    /// Refresh exactly the ids named by an edit patch.
    pub fn update(&mut self, ids: impl IntoIterator<Item = BlockId>, document: &Document) {
        for id in ids {
            self.replace(id, document.block(id));
        }
    }

    pub fn pin(&mut self, kind: EntityKind, value: &str) {
        let display = value.trim().to_owned();
        if !display.is_empty() {
            self.pinned.insert((kind, key(&display)), display);
        }
    }

    pub fn unpin(&mut self, kind: EntityKind, value: &str) {
        self.pinned.remove(&(kind, key(value)));
    }

    pub fn pinned(&self) -> Vec<(EntityKind, String)> {
        self.pinned
            .iter()
            .map(|((kind, _), display)| (*kind, display.clone()))
            .collect()
    }

    /// Characters in deterministic name order, with occurrences in document
    /// order.
    ///
    /// The aggregates and per-block contributions are the index's two views of
    /// these facts. The document is consulted only to order the stable block
    /// ids; character recognition is not repeated here.
    pub fn characters(&self, document: &Document) -> Vec<NavigatorCharacter> {
        let mut characters: BTreeMap<String, NavigatorCharacter> = self
            .entities
            .iter()
            .filter_map(|((kind, character_key), aggregate)| {
                if *kind != EntityKind::Character {
                    return None;
                }
                let display = aggregate
                    .displays
                    .iter()
                    .max_by_key(|(display, count)| (**count, std::cmp::Reverse(*display)))
                    .map(|(display, _)| normalize_character(display))
                    .unwrap_or_else(|| character_key.clone());
                Some((
                    character_key.clone(),
                    NavigatorCharacter {
                        name: display,
                        frequency: aggregate.frequency,
                        blocks: Vec::new(),
                    },
                ))
            })
            .collect();

        for block in document.blocks() {
            let Some(contributions) = self.by_block.get(&block.id()) else {
                continue;
            };
            for contribution in contributions {
                if contribution.kind == EntityKind::Character {
                    if let Some(character) = characters.get_mut(&contribution.key) {
                        character.blocks.push(block.id());
                    }
                }
            }
        }

        characters.into_values().collect()
    }

    pub fn complete(
        &self,
        kind: EntityKind,
        prefix: &str,
        suppressed: &[String],
    ) -> Vec<Completion> {
        let wanted = key(prefix);
        let suppressed: Vec<String> = suppressed.iter().map(|value| key(value)).collect();
        let mut candidates: BTreeMap<String, Completion> = BTreeMap::new();

        for ((candidate_kind, candidate_key), aggregate) in &self.entities {
            if *candidate_kind != kind
                || !candidate_key.starts_with(&wanted)
                || suppressed.contains(candidate_key)
            {
                continue;
            }
            let display = aggregate
                .displays
                .iter()
                .max_by_key(|(display, count)| (**count, std::cmp::Reverse(*display)))
                .map(|(display, _)| display.clone())
                .unwrap_or_else(|| candidate_key.clone());
            candidates.insert(
                candidate_key.clone(),
                Completion {
                    kind,
                    value: display,
                    frequency: aggregate.frequency,
                    recency: aggregate.recency,
                    pinned: self
                        .pinned
                        .contains_key(&(*candidate_kind, candidate_key.clone())),
                },
            );
        }
        for ((candidate_kind, candidate_key), display) in &self.pinned {
            if *candidate_kind == kind
                && candidate_key.starts_with(&wanted)
                && !suppressed.contains(candidate_key)
            {
                candidates
                    .entry(candidate_key.clone())
                    .and_modify(|candidate| candidate.pinned = true)
                    .or_insert_with(|| Completion {
                        kind,
                        value: display.clone(),
                        frequency: 0,
                        recency: 0,
                        pinned: true,
                    });
            }
        }
        if kind == EntityKind::TimeOfDay {
            for value in TIMES {
                let candidate_key = key(value);
                if candidate_key.starts_with(&wanted) && !suppressed.contains(&candidate_key) {
                    candidates.entry(candidate_key).or_insert(Completion {
                        kind,
                        value: value.to_owned(),
                        frequency: 0,
                        recency: 0,
                        pinned: false,
                    });
                }
            }
        }
        if kind == EntityKind::ScenePrefix {
            for value in SCENE_PREFIXES {
                let candidate_key = key(value);
                if candidate_key.starts_with(&wanted) && !suppressed.contains(&candidate_key) {
                    candidates.entry(candidate_key).or_insert(Completion {
                        kind,
                        value: value.to_owned(),
                        frequency: 0,
                        recency: 0,
                        pinned: false,
                    });
                }
            }
        }

        let mut result: Vec<_> = candidates.into_values().collect();
        result.sort_by(|a, b| {
            let a_exact = key(&a.value) == wanted;
            let b_exact = key(&b.value) == wanted;
            b_exact
                .cmp(&a_exact)
                .then_with(|| b.frequency.cmp(&a.frequency))
                .then_with(|| b.recency.cmp(&a.recency))
                .then_with(|| a.value.cmp(&b.value))
        });
        result
    }

    fn replace(&mut self, id: BlockId, block: Option<&Block>) {
        if let Some(old) = self.by_block.remove(&id) {
            for contribution in old {
                let aggregate_key = (contribution.kind, contribution.key);
                // Saturating, not `-= 1`: the counts and `by_block` are two
                // views of one fact, and if they ever disagree the answer is a
                // slightly wrong completion list, not a panicked actor thread
                // that takes the writer's session with it (F12). Reaching zero
                // drops the entity, which is also how a desynchronised count
                // repairs itself.
                let remove = if let Some(aggregate) = self.entities.get_mut(&aggregate_key) {
                    aggregate.frequency = aggregate.frequency.saturating_sub(1);
                    if let Some(count) = aggregate.displays.get_mut(&contribution.display) {
                        *count = count.saturating_sub(1);
                        if *count == 0 {
                            aggregate.displays.remove(&contribution.display);
                        }
                    }
                    aggregate.frequency == 0
                } else {
                    false
                };
                if remove {
                    self.entities.remove(&aggregate_key);
                }
            }
        }
        let Some(block) = block else { return };
        let contributions = contributions(block);
        if contributions.is_empty() {
            return;
        }
        self.clock += 1;
        for contribution in &contributions {
            let aggregate = self
                .entities
                .entry((contribution.kind, contribution.key.clone()))
                .or_default();
            aggregate.frequency += 1;
            aggregate.recency = self.clock;
            *aggregate
                .displays
                .entry(contribution.display.clone())
                .or_default() += 1;
        }
        self.by_block.insert(id, contributions);
    }
}

fn contributions(block: &Block) -> Vec<Contribution> {
    let text = block.text().trim();
    match block.kind() {
        BlockKind::Character => {
            let display = text.to_owned();
            let normalized = normalize_character(text);
            (!normalized.is_empty())
                .then(|| Contribution {
                    kind: EntityKind::Character,
                    key: key(&normalized),
                    display,
                })
                .into_iter()
                .collect()
        }
        BlockKind::SceneHeading => scene_contributions(text),
        BlockKind::Transition => (!text.is_empty())
            .then(|| Contribution {
                kind: EntityKind::Transition,
                key: key(text),
                display: text.to_owned(),
            })
            .into_iter()
            .collect(),
        _ => Vec::new(),
    }
}

fn scene_contributions(text: &str) -> Vec<Contribution> {
    let parts = scene_heading_parts(text);
    let mut result = Vec::new();
    if !parts.prefix.is_empty() {
        result.push(Contribution {
            kind: EntityKind::ScenePrefix,
            key: key(&parts.prefix),
            display: parts.prefix,
        });
    }
    if !parts.location.is_empty() {
        result.push(Contribution {
            kind: EntityKind::Location,
            key: key(&parts.location),
            display: parts.location,
        });
    }
    if let Some(time) = parts.time_of_day {
        result.push(Contribution {
            kind: EntityKind::TimeOfDay,
            key: key(&time),
            display: time,
        });
    }
    result
}

/// Splits a recognised or forced scene heading for the navigator and entity
/// index. Scene-number recognition stays in `fountain::syntax`; this function
/// only gives names to the display parts after the parser has already decided
/// the block is a scene heading.
pub fn scene_heading_parts(text: &str) -> SceneHeadingParts {
    const PREFIXES: [&str; 12] = [
        "INT./EXT.",
        "INT./EXT",
        "INT/EXT.",
        "INT/EXT",
        "I/E.",
        "I/E",
        "INT.",
        "INT",
        "EXT.",
        "EXT",
        "EST.",
        "EST",
    ];

    let (heading, scene_number) = split_scene_number(text);
    let heading = heading.trim();
    let upper = key(heading);
    let (prefix, rest) = PREFIXES
        .into_iter()
        .find_map(|prefix| {
            upper.strip_prefix(prefix).and_then(|rest| {
                (rest.is_empty() || rest.starts_with(char::is_whitespace))
                    .then(|| (prefix, rest.trim()))
            })
        })
        .unwrap_or(("", upper.as_str()));
    let (location, time_of_day) =
        rest.rsplit_once(" - ")
            .map_or((rest, None), |(location, time)| {
                (
                    location.trim(),
                    (!time.trim().is_empty()).then(|| time.trim()),
                )
            });

    SceneHeadingParts {
        prefix: prefix.to_owned(),
        location: location.to_owned(),
        time_of_day: time_of_day.map(str::to_owned),
        scene_number: scene_number.map(str::to_owned),
    }
}

pub fn normalize_character(text: &str) -> String {
    let mut value = text.trim();
    loop {
        let trimmed = value.trim_end();
        let Some(stripped) = strip_extension(trimmed) else {
            return trimmed.to_owned();
        };
        value = stripped;
    }
}

/// `text` without a trailing character extension, or `None` if it does not end
/// with one.
///
/// The extension is the last parenthesised group, and it matches when its
/// *letters* are one of [`CHARACTER_EXTENSIONS`]. Everything the writer might
/// vary is therefore ignored — case, the periods in `(V.O.)`, and a typographic
/// `’` in `(CONT’D)` — while anything else in parentheses, `(JR)` or `(32)` or
/// `(VOICE)`, is a name and is kept.
///
/// The split is `text`'s own byte index of that `(`, never a length measured on
/// an uppercased copy. That is F11: uppercasing is not length-preserving — `ſ` →
/// `S` and `ı` → `I` each lose a byte — and two of them in one extension is
/// enough to put the split inside a character and panic the actor thread.
/// `BOB (ſUBTıTLE)` did exactly that. Nothing here allocates, and nothing longer
/// than the trailing group is examined.
fn strip_extension(text: &str) -> Option<&str> {
    let inside = text.strip_suffix(')')?;
    let open = inside.rfind('(')?;
    CHARACTER_EXTENSIONS
        .into_iter()
        .any(|extension| letters_uppercase_to(&inside[open + 1..], extension))
        .then(|| &text[..open])
}

/// Whether `text`'s letters and digits, uppercased, are exactly `extension`.
fn letters_uppercase_to(text: &str, extension: &str) -> bool {
    text.chars()
        .flat_map(char::to_uppercase)
        .filter(|c| c.is_alphanumeric())
        .eq(extension.chars())
}

fn key(value: &str) -> String {
    value.trim().to_uppercase()
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::EditCommand;

    #[test]
    fn extensions_share_a_key_but_keep_the_display() {
        let document = Document::parse("BOB (V.O.)\nHello.\n\nBOB (O.S.)\nAgain.\n");
        let index = EntityIndex::build(&document);
        let result = index.complete(EntityKind::Character, "bo", &[]);
        assert_eq!(result.len(), 1);
        assert_eq!(result[0].frequency, 2);
        assert!(result[0].value.starts_with("BOB "));
    }

    #[test]
    fn removing_the_last_occurrence_removes_the_entity_incrementally() {
        let mut document = Document::parse("INT. KITCHEN - DAY\n");
        let id = document.blocks()[0].id();
        let mut index = EntityIndex::build(&document);
        document
            .apply(EditCommand::SetKind {
                block: id,
                kind: BlockKind::Action,
                forced: true,
            })
            .unwrap();
        index.update([id], &document);
        assert!(index.complete(EntityKind::Location, "", &[]).is_empty());
    }

    #[test]
    fn ranking_is_exact_then_frequency_then_recency_and_deterministic() {
        let document = Document::parse("AL\nOne.\n\nALICE\nTwo.\n\nALICE\nThree.\n\nALAN\nFour.\n");
        let index = EntityIndex::build(&document);
        let values: Vec<_> = index
            .complete(EntityKind::Character, "AL", &[])
            .into_iter()
            .map(|candidate| candidate.value)
            .collect();
        assert_eq!(values, ["AL", "ALICE", "ALAN"]);
    }

    #[test]
    fn standard_times_are_available_without_occurrences() {
        let index = EntityIndex::default();
        let values: Vec<_> = index
            .complete(EntityKind::TimeOfDay, "CONT", &[])
            .into_iter()
            .map(|candidate| candidate.value)
            .collect();
        assert_eq!(values, ["CONTINUOUS"]);
    }

    #[test]
    fn extensions_are_stripped_whatever_case_they_arrive_in() {
        assert_eq!(normalize_character("BOB (V.O.)"), "BOB");
        assert_eq!(normalize_character("Bob (v.o.)"), "Bob");
        assert_eq!(normalize_character("BOB (Cont'd)"), "BOB");
        assert_eq!(normalize_character("  BOB (O.S.) (CONT'D)  "), "BOB");
        assert_eq!(normalize_character("BOB"), "BOB");
        assert_eq!(normalize_character("(V.O.)"), "");
        assert_eq!(normalize_character(""), "");
    }

    /// ADR 0031. A dropped period is a typo, not a different character: every
    /// one of these was its own entity in the index before, so a script with
    /// `BOB` and `BOB (O.S)` in it offered two Bobs and counted each half.
    #[test]
    fn an_extension_missing_its_punctuation_is_still_an_extension() {
        assert_eq!(normalize_character("BOB (O.S)"), "BOB");
        assert_eq!(normalize_character("BOB (OS)"), "BOB");
        assert_eq!(normalize_character("BOB (V.O)"), "BOB");
        assert_eq!(normalize_character("BOB (VO.)"), "BOB");
        assert_eq!(normalize_character("BOB (vo)"), "BOB");
        assert_eq!(normalize_character("BOB (O.C)"), "BOB");
        // A typographic apostrophe is the one a word processor would have left.
        assert_eq!(normalize_character("BOB (CONT’D)"), "BOB");
        assert_eq!(normalize_character("BOB (CONTD)"), "BOB");
        // Stacked, and mixed between the two spellings.
        assert_eq!(normalize_character("BOB (O.S) (CONT’D)"), "BOB");
    }

    #[test]
    fn a_name_that_merely_resembles_an_extension_keeps_it() {
        // Parenthesised, but not one of the five: a name, and it stays one.
        assert_eq!(normalize_character("BOB (VOICE)"), "BOB (VOICE)");
        assert_eq!(normalize_character("BOB (JR)"), "BOB (JR)");
        assert_eq!(normalize_character("BOB (32)"), "BOB (32)");
        assert_eq!(normalize_character("BOB (O S T)"), "BOB (O S T)");
        // Not a parenthesised group at all: no `(` to split on.
        assert_eq!(normalize_character("V.O.)"), "V.O.)");
        assert_eq!(normalize_character("O.)"), "O.)");
        assert_eq!(normalize_character("BOB V.O."), "BOB V.O.");
        // The group is not at the end.
        assert_eq!(normalize_character("BOB (V.O.) JR"), "BOB (V.O.) JR");
    }

    /// F11. Uppercasing is not length-preserving, so the old check — uppercase
    /// the cue, then slice the *original* by the uppercased suffix's length —
    /// measured one string and cut another. `ſ` and `ı` each lose a byte on the
    /// way to `S` and `I`, and two of them in `(SUBTITLE)` moved the split two
    /// bytes right, into the middle of the `ſ`: a char-boundary panic on the
    /// actor thread. One of them was merely wrong, which is how it got missed.
    #[test]
    fn an_extension_that_shortens_when_uppercased_neither_panics_nor_mis_slices() {
        assert_eq!(normalize_character("BOB (ſUBTıTLE)"), "BOB");
        assert_eq!(normalize_character("BOB (SUBTıTLE)"), "BOB");
        assert_eq!(normalize_character("BOB (ſUBTITLE)"), "BOB");
    }

    #[test]
    fn a_non_ascii_cue_survives_normalisation_intact() {
        assert_eq!(normalize_character("ANDRÉ (V.O.)"), "ANDRÉ");
        assert_eq!(normalize_character("STRAßE (V.O.)"), "STRAßE");
        assert_eq!(normalize_character("김민준 (O.S.)"), "김민준");
        // A non-BMP cue: four bytes per character, and none of them a boundary
        // the extension check may guess at.
        assert_eq!(normalize_character("𝐁𝐎𝐁 (CONT'D)"), "𝐁𝐎𝐁");
        assert_eq!(normalize_character("𝐁𝐎𝐁"), "𝐁𝐎𝐁");
    }

    #[test]
    fn no_cue_at_all_can_panic_the_index() {
        // Every prefix and suffix of a cue built out of the awkward cases, so
        // that a split landing anywhere is exercised rather than argued about.
        let cue = "Bƒob ſı (ſUBTıTLE) (v.o.) 𝐁 é(CONT'D)";
        for end in 0..=cue.len() {
            if !cue.is_char_boundary(end) {
                continue;
            }
            for start in 0..=end {
                if cue.is_char_boundary(start) {
                    normalize_character(&cue[start..end]);
                }
            }
        }
    }

    /// F12. The counts and `by_block` are two views of one fact; an unchecked
    /// `-= 1` turned any disagreement between them into a panic on the actor
    /// thread. The index is a cache of completions — the worst it may do when it
    /// is wrong is offer a wrong completion.
    #[test]
    fn a_desynchronised_count_degrades_instead_of_panicking() {
        let document = Document::parse("BOB\nHello.\n\nBOB\nAgain.\n");
        let first = document.blocks()[0].id();
        let mut index = EntityIndex::build(&document);
        let entity = (EntityKind::Character, "BOB".to_owned());
        assert_eq!(index.entities[&entity].frequency, 2);

        // What a lost update looks like from here: the blocks still claim their
        // contributions, the aggregate has already forgotten both of them.
        let aggregate = index.entities.get_mut(&entity).unwrap();
        aggregate.frequency = 0;
        aggregate.displays.clear();

        index.replace(first, None);
        assert!(index.complete(EntityKind::Character, "", &[]).is_empty());
    }

    /// The invariant behind the decrement: after any run of edits, the counts
    /// the index has been maintaining incrementally are the counts a full scan
    /// of the same document would produce. Recency is deliberately not compared
    /// — it is a clock, and an incremental index has ticked it a different
    /// number of times than a rebuild has.
    #[test]
    fn incremental_counts_match_a_rebuild_after_a_run_of_edits() {
        let mut document =
            Document::parse("BOB\nHi.\n\nINT. KITCHEN - DAY\n\nBOB (V.O.)\nAgain.\n\nCUT TO:\n");
        let mut index = EntityIndex::build(&document);
        let ids: Vec<_> = document.blocks().iter().map(|block| block.id()).collect();

        for (step, id) in ids.iter().enumerate() {
            if let Ok(result) = document.apply(EditCommand::ReplaceText {
                block: *id,
                range: 0..0,
                with: format!("{step} "),
            }) {
                index.update(result.changed, &document);
            }
        }
        for id in &ids {
            if let Ok(result) = document.apply(EditCommand::SetKind {
                block: *id,
                kind: BlockKind::Action,
                forced: true,
            }) {
                index.update(result.changed, &document);
            }
        }

        assert_eq!(counts(&index), counts(&EntityIndex::build(&document)));
    }

    fn counts(index: &EntityIndex) -> Vec<String> {
        index
            .entities
            .iter()
            .map(|((kind, key), aggregate)| {
                format!(
                    "{kind:?} {key} x{} {:?}",
                    aggregate.frequency, aggregate.displays
                )
            })
            .collect()
    }

    #[test]
    fn completion_p99_is_under_five_milliseconds_at_the_exit_criteria_size() {
        let mut source = String::new();
        for character in 0..60 {
            source.push_str(&format!("CHARACTER {character}\nLine.\n\n"));
        }
        for location in 0..200 {
            source.push_str(&format!("INT. LOCATION {location} - DAY\n\n"));
        }
        let index = EntityIndex::build(&Document::parse(&source));
        let mut samples = Vec::with_capacity(2_000);
        for _ in 0..2_000 {
            let start = std::time::Instant::now();
            std::hint::black_box(index.complete(EntityKind::Location, "LOC", &[]));
            samples.push(start.elapsed());
        }
        samples.sort_unstable();
        let p99 = samples[samples.len() * 99 / 100];
        assert!(
            p99 < std::time::Duration::from_millis(5),
            "completion p99 was {p99:?}"
        );
    }

    #[test]
    fn scene_heading_parts_include_authored_numbers_and_forced_headings() {
        assert_eq!(
            scene_heading_parts("INT./EXT. CAR - MOMENTS LATER #12A#"),
            SceneHeadingParts {
                prefix: "INT./EXT.".to_owned(),
                location: "CAR".to_owned(),
                time_of_day: Some("MOMENTS LATER".to_owned()),
                scene_number: Some("12A".to_owned()),
            }
        );
        assert_eq!(
            scene_heading_parts("A DREAM - NIGHT"),
            SceneHeadingParts {
                prefix: String::new(),
                location: "A DREAM".to_owned(),
                time_of_day: Some("NIGHT".to_owned()),
                scene_number: None,
            }
        );
    }

    #[test]
    fn navigator_characters_use_index_counts_and_document_order() {
        let document =
            Document::parse("BOB (V.O.)\nFirst.\n\nALICE\nSecond.\n\nBOB (O.S.)\nThird.\n");
        let index = EntityIndex::build(&document);
        let characters = index.characters(&document);
        assert_eq!(
            characters
                .iter()
                .map(|character| (
                    character.name.as_str(),
                    character.frequency,
                    character.blocks.len()
                ))
                .collect::<Vec<_>>(),
            vec![("ALICE", 1, 1), ("BOB", 2, 2)]
        );
        assert!(
            characters[1].blocks[0] < characters[1].blocks[1],
            "occurrences are in document order"
        );
    }
}
