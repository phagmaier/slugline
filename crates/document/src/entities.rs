//! Incremental screenplay entity index and completion ranking (§7).
//!
//! The index remembers the contribution of each block.  Updating a patch removes
//! only the old contribution for the affected ids and reads only their new
//! blocks; the edit hot path therefore never scans the document.

use std::collections::{BTreeMap, HashMap};

use crate::{Block, BlockId, BlockKind, Document};

const CHARACTER_EXTENSIONS: [&str; 5] = ["(V.O.)", "(O.S.)", "(O.C.)", "(CONT'D)", "(SUBTITLE)"];
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
                let remove = if let Some(aggregate) = self.entities.get_mut(&aggregate_key) {
                    aggregate.frequency -= 1;
                    if let Some(count) = aggregate.displays.get_mut(&contribution.display) {
                        *count -= 1;
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
    let upper = key(text);
    let Some((prefix, rest)) = SCENE_PREFIXES
        .into_iter()
        .find_map(|prefix| upper.strip_prefix(prefix).map(|rest| (prefix, rest.trim())))
    else {
        return Vec::new();
    };
    let (location, time) = rest
        .rsplit_once(" - ")
        .map_or((rest, None), |(location, time)| {
            (location.trim(), Some(time.trim()))
        });
    let mut result = vec![Contribution {
        kind: EntityKind::ScenePrefix,
        key: key(prefix),
        display: prefix.to_owned(),
    }];
    if !location.is_empty() {
        result.push(Contribution {
            kind: EntityKind::Location,
            key: key(location),
            display: location.to_owned(),
        });
    }
    if let Some(time) = time.filter(|time| !time.is_empty()) {
        result.push(Contribution {
            kind: EntityKind::TimeOfDay,
            key: key(time),
            display: time.to_owned(),
        });
    }
    result
}

pub fn normalize_character(text: &str) -> String {
    let mut value = text.trim();
    loop {
        let trimmed = value.trim_end();
        let Some(extension) = CHARACTER_EXTENSIONS
            .into_iter()
            .find(|extension| trimmed.to_uppercase().ends_with(extension))
        else {
            return trimmed.to_owned();
        };
        value = trimmed[..trimmed.len() - extension.len()].trim_end();
    }
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
}
