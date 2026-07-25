//! The document half of the §6 bridge API.
//!
//! Three rules govern everything in this module:
//!
//! 1. **Every offset is a UTF-16 code-unit offset named `*_utf16`** (§2.4), and
//!    it is converted through [`crate::offsets`] against the text of the block it
//!    points into. An offset that does not land on a boundary comes back as a
//!    rejection, never as a rounded guess (ADR 0001).
//! 2. **Nothing here holds a document.** Every function hands a closure to the
//!    actor thread (§2.3), which owns the only `Document`.
//! 3. **An edit answers with a patch, not a document** (§6). [`EditResult`]
//!    carries the blocks that changed and where the ones that appeared went, so
//!    Dart never refetches.
//!
//! The types below deliberately mirror `slugline_document`'s rather than reusing
//! them: the model speaks UTF-8 byte offsets (ADR 0008) and this surface speaks
//! UTF-16, and a type that is the same shape in both encodings is a type that
//! will eventually be passed to the wrong one.

use std::time::Instant;

use flutter_rust_bridge::frb;

use slugline_document as model;

use crate::actor::actor;
use crate::api::events::{emit, CoreEvent};
use crate::offsets;
use crate::state::Session;

// ---------------------------------------------------------------------------
// Handles and views
// ---------------------------------------------------------------------------

/// A document open in the core. Dart holds one of these for the lifetime of an
/// editor; it is not a pointer, so a stale one is refused rather than followed.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct DocumentHandle {
    pub id: u64,
}

/// The element types of §3.1.
///
/// Flat on purpose. `BlockKind::Section` carries a level in the model, and an
/// enum with a payload becomes a `freezed` union in Dart — which the editor
/// would then have to destructure on every block it paints, and which cannot be
/// a map key. The level rides alongside in [`BlockView::section_level`] instead.
/// See ADR 0009.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum BlockKind {
    SceneHeading,
    Action,
    Character,
    Dialogue,
    Parenthetical,
    Transition,
    Centered,
    Lyric,
    Section,
    Synopsis,
    Note,
    PageBreak,
    /// Valid Fountain the editor does not model. Round-trips verbatim and
    /// refuses every edit (§3.2).
    Opaque,
}

/// One block, as the editor needs it.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BlockView {
    /// `BlockId` (§3.1). Stable for the life of the document, never reused, and
    /// the key Flutter builds its list against.
    pub id: u64,
    pub kind: BlockKind,
    /// 1–6 when `kind` is `Section`, 0 otherwise.
    pub section_level: u8,
    /// The user-visible text, with Fountain emphasis markup retained inline.
    pub text: String,
    pub forced: bool,
    pub dual: bool,
    /// The block cannot be edited. Only `Opaque` blocks are.
    pub read_only: bool,
}

/// A caret position, in document coordinates (§3.3).
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct DocPosition {
    pub block: u64,
    pub offset_utf16: u32,
}

/// A selection, which may be empty (a caret) and may run in either direction.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct DocSelection {
    pub anchor: DocPosition,
    pub focus: DocPosition,
}

/// A block to be inserted, before the document has given it an identity.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct NewBlock {
    pub kind: BlockKind,
    pub section_level: u8,
    pub text: String,
    pub forced: bool,
    pub dual: bool,
}

/// Every mutation of a document (§3.4).
///
/// `SetTitlePage` is absent: the title page is edited in Phase 7, and a command
/// with no caller is scaffolding (§1.4).
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum EditCommand {
    ReplaceText {
        block: u64,
        start_utf16: u32,
        end_utf16: u32,
        with: String,
    },
    SplitBlock {
        block: u64,
        at_utf16: u32,
    },
    /// Merges `first` with the block that follows it.
    MergeBlocks {
        first: u64,
    },
    SetKind {
        block: u64,
        kind: BlockKind,
        section_level: u8,
        forced: bool,
    },
    InsertBlocks {
        after: Option<u64>,
        blocks: Vec<NewBlock>,
    },
    DeleteRange {
        from: DocPosition,
        to: DocPosition,
    },
    SetDual {
        block: u64,
        dual: bool,
    },
}

/// What to look for (§6's `FindQuery`).
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct FindQuery {
    pub text: String,
    pub case_sensitive: bool,
    pub whole_word: bool,
    /// When empty, every block is searched. Otherwise only these kinds are —
    /// §Phase 3's optional element filter. A `Section` here matches every level.
    pub kinds: Vec<BlockKind>,
}

/// One hit (§6's `Match`).
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct FindMatch {
    pub block: u64,
    pub start_utf16: u32,
    pub end_utf16: u32,
}

/// A block that appeared, and the index it appeared at.
///
/// The index is the block's position **after** the edit, so Dart can apply the
/// patch as: drop `removed`, update `changed`, then insert these in ascending
/// index order.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct InsertedBlock {
    pub index: u32,
    pub block: BlockView,
}

/// What an edit did, as a patch Flutter applies to its own copy (§6).
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct EditResult {
    pub changed: Vec<BlockView>,
    pub removed: Vec<u64>,
    pub inserted: Vec<InsertedBlock>,
    /// The caret after the edit. `None` when there is no block to anchor it to.
    pub selection: Option<DocSelection>,
    /// Blocks in the document afterwards, so Dart can assert its copy is right
    /// rather than assume it.
    pub block_count: u32,
}

/// Why an edit did not apply.
///
/// A rejection is a value rather than an exception because two of these are
/// ordinary user actions, not bugs: typing inside a boneyard comment, and
/// backspacing at the very start of the script. Flutter beeps; it does not catch.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum EditRejection {
    /// No block with that id — it was deleted, or the handle is stale.
    UnknownBlock,
    /// Past the end of a block, or inside a character.
    BadOffset,
    /// The command needs a block after this one and there is none.
    NoBlockAfter,
    BadRange,
    /// The block round-trips verbatim and cannot be edited (§3.2).
    NotEditable,
    /// The command would leave a block in a state the model cannot represent.
    InvalidBlock,
    /// A UTF-16 offset that lands between the halves of a surrogate pair, or
    /// past the end of the text (ADR 0001). Nothing is rounded.
    BadUtf16Offset,
    /// No document with that handle.
    NoSuchDocument,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum EditOutcome {
    Applied {
        result: EditResult,
    },
    Rejected {
        reason: EditRejection,
        /// Human-readable, for the log and for test failures. Not for the UI.
        message: String,
    },
}

// ---------------------------------------------------------------------------
// Lifecycle
// ---------------------------------------------------------------------------

/// A new, empty script.
///
/// Phase 2 has no persistence: a document lives in memory until [`doc_close`] or
/// process exit. `library_open`/`library_create` (§6) arrive with `storage` in
/// Phase 4 and take over this job.
#[frb(sync)]
pub fn doc_new() -> DocumentHandle {
    DocumentHandle {
        id: actor().run(|state| state.open(model::Document::blank())),
    }
}

/// Parses Fountain source into a new document. Total: every input parses.
#[frb(sync)]
pub fn doc_parse(source: String) -> DocumentHandle {
    DocumentHandle {
        id: actor().run(move |state| {
            let document = model::Document::parse(&source);
            // A file that parses to nothing still needs somewhere to type.
            state.open(if document.blocks().is_empty() {
                model::Document::blank()
            } else {
                document
            })
        }),
    }
}

#[frb(sync)]
pub fn doc_close(handle: DocumentHandle) {
    actor().run(move |state| state.close(handle.id));
}

// ---------------------------------------------------------------------------
// Reads
// ---------------------------------------------------------------------------

#[frb(sync)]
pub fn doc_block_count(handle: DocumentHandle) -> u32 {
    actor().run(move |state| {
        state
            .session(handle.id)
            .map(|session| clamp_u32(session.document().blocks().len()))
            .unwrap_or_default()
    })
}

/// Blocks `from..to`, clamped to the document. Out-of-range asks are answered
/// with what exists, because the caller is a scrolling viewport racing an edit.
#[frb(sync)]
pub fn doc_blocks(handle: DocumentHandle, from: u32, to: u32) -> Vec<BlockView> {
    actor().run(move |state| {
        let Some(session) = state.session(handle.id) else {
            return Vec::new();
        };
        let blocks = session.document().blocks();
        let start = (from as usize).min(blocks.len());
        let end = (to as usize).clamp(start, blocks.len());
        blocks[start..end].iter().map(view_of).collect()
    })
}

/// The document as Fountain.
///
/// Phase 2 saves nothing, so this exists to let a test assert what the core
/// actually holds. Phase 4's `doc_save` writes the same bytes through `storage`.
#[frb(sync)]
pub fn doc_source(handle: DocumentHandle) -> String {
    actor().run(move |state| {
        state
            .session(handle.id)
            .map(|session| session.document().serialise())
            .unwrap_or_default()
    })
}

/// The Fountain text between two positions, for the clipboard. `None` when
/// either position does not resolve.
#[frb(sync)]
pub fn doc_extract(handle: DocumentHandle, from: DocPosition, to: DocPosition) -> Option<String> {
    actor().run(move |state| {
        let session = state.session(handle.id)?;
        let document = session.document();
        let from = to_model_position(document, from).ok()?;
        let to = to_model_position(document, to).ok()?;
        document.extract(from, to).ok()
    })
}

/// Every match of `query`, in document order (§6's `find`).
///
/// The whole list, not a page of it: the find bar shows a live count, and a
/// count of "the first fifty" is not a count. A feature-length script is a few
/// hundred kilobytes, so this is a scan of less text than one screenshot.
#[frb(sync)]
pub fn doc_find(handle: DocumentHandle, query: FindQuery) -> Vec<FindMatch> {
    actor().run(move |state| {
        let Some(session) = state.session(handle.id) else {
            return Vec::new();
        };
        let document = session.document();
        document
            .find(&model_query(query))
            .into_iter()
            .filter_map(|hit| match_view(document, &hit))
            .collect()
    })
}

/// The element type Tab would move the caret's block to, without moving it.
///
/// The element bar shows this, so that "Tab" on screen means something specific
/// rather than being a key the writer has to try. It answers from the same table
/// [`doc_tab`] acts on — there is no second copy of it in Dart (§2.1).
#[frb(sync)]
pub fn doc_tab_target(handle: DocumentHandle, block: u64, shift: bool) -> Option<BlockKind> {
    actor().run(move |state| {
        let session = state.session(handle.id)?;
        let (kind, _) = kind_view(tab_target(
            session.document(),
            model::BlockId(block),
            shift,
        )?);
        Some(kind)
    })
}

/// The character cue this block's text already names, if the script has one.
///
/// §Phase 3's "typing an existing character name in an Action-position block
/// suggests Character". A suggestion and nothing else: the editor shows the name
/// beside the element bar, and Tab is what accepts it.
#[frb(sync)]
pub fn doc_character_suggestion(handle: DocumentHandle, block: u64) -> Option<String> {
    actor().run(move |state| {
        state
            .session(handle.id)?
            .document()
            .character_suggestion(model::BlockId(block))
            .map(str::to_owned)
    })
}

// ---------------------------------------------------------------------------
// Writes
// ---------------------------------------------------------------------------

/// Applies one command.
///
/// `before` is the selection the user had **before** the edit, so undo can put
/// the caret back where it was rather than where the edit left it (§3.4). Dart
/// owns the caret, so only Dart can say.
#[frb(sync)]
pub fn doc_apply(
    handle: DocumentHandle,
    command: EditCommand,
    before: Option<DocSelection>,
) -> EditOutcome {
    actor().run(move |state| {
        let now = Instant::now();
        let Some(session) = state.session_mut(handle.id) else {
            return no_such_document();
        };
        let document = session.editing(now);
        let command = match to_model_command(document, command) {
            Ok(command) => command,
            Err(rejection) => return rejection,
        };
        let before = match to_model_selection(document, before) {
            Ok(selection) => selection,
            Err(rejection) => return rejection,
        };
        let result = document.apply_with_selection(command, before);
        inferring(session, before, result)
    })
}

/// Enter, with §Phase 3's table applied to whatever it creates.
///
/// Composed here rather than in `document` for ADR 0010's reason: the bridge
/// writes the plan, the document groups it, and one keystroke is therefore one
/// undo step even though it may be a delete, a split and a kind change. The
/// table itself is `document`'s — Dart never decides what follows an element.
#[frb(sync)]
pub fn doc_enter(handle: DocumentHandle, at: DocSelection) -> EditOutcome {
    actor().run(move |state| {
        let Some(session) = state.session_mut(handle.id) else {
            return no_such_document();
        };
        // Enter is structural: it neither joins the run of typing before it nor
        // leaves one open behind it.
        let document = session.interrupt();
        let at = match to_model_selection(document, Some(at)) {
            Ok(selection) => selection.expect("Some in, Some out"),
            Err(rejection) => return rejection,
        };
        let result = document.apply_group(Some(at), |group| enter(group, at));
        inferring(session, Some(at), result)
    })
}

/// Tab, or Shift+Tab, on the block the caret is in.
///
/// `None` — not a rejection — where the table says Tab does nothing. There is
/// nothing to report and nothing to beep about: the writer pressed a key that
/// means "next element type" in a place that has no next element type, and the
/// editor's answer is to leave the document exactly as it was.
#[frb(sync)]
pub fn doc_tab(handle: DocumentHandle, at: DocSelection, shift: bool) -> Option<EditOutcome> {
    actor().run(move |state| {
        let session = state.session_mut(handle.id)?;
        let document = session.interrupt();
        let id = model::BlockId(at.focus.block);
        let kind = tab_target(document, id, shift)?;
        let before = match to_model_selection(document, Some(at)) {
            Ok(selection) => selection,
            Err(rejection) => return Some(rejection),
        };
        // §Phase 3: setting a type explicitly pins it, so that automatic
        // re-classification does not take it back on the next keystroke.
        let result = document.apply_with_selection(
            model::EditCommand::SetKind {
                block: id,
                kind,
                forced: true,
            },
            before,
        );
        Some(inferring(session, before, result))
    })
}

/// Replaces every match of `query` with `with`, as one undo transaction.
#[frb(sync)]
pub fn doc_replace_all(handle: DocumentHandle, query: FindQuery, with: String) -> EditOutcome {
    actor().run(move |state| {
        let Some(session) = state.session_mut(handle.id) else {
            return no_such_document();
        };
        let document = session.interrupt();
        let result = document.replace_all(&model_query(query), &with, None);
        // Deliberately not re-classified: see `Document::replace_all`.
        outcome(session, result)
    })
}

/// Inserts `text` at `at`, replacing the selection if there is one, as **one**
/// undo transaction.
///
/// `plain` is `Ctrl+Shift+V` (§Phase 2): the text becomes Action blocks and no
/// element is inferred from it. Otherwise the text is parsed as Fountain, and
/// the blocks it produces keep their own kinds.
#[frb(sync)]
pub fn doc_paste(
    handle: DocumentHandle,
    at: DocSelection,
    text: String,
    plain: bool,
) -> EditOutcome {
    actor().run(move |state| {
        let Some(session) = state.session_mut(handle.id) else {
            return no_such_document();
        };
        // A paste is structural, so it neither joins the run of typing before it
        // nor leaves one open behind it.
        let document = session.interrupt();
        let at = match to_model_selection(document, Some(at)) {
            Ok(selection) => selection.expect("Some in, Some out"),
            Err(rejection) => return rejection,
        };
        let blocks = if plain {
            plain_blocks(&text)
        } else {
            model::parse_blocks(&text)
        };
        let result = document.apply_group(Some(at), |group| paste(group, at, blocks));
        // A plain paste is the one edit that is asked not to infer anything
        // (§Phase 2), and that has to hold for the blocks around it too: the
        // whole point of `Ctrl+Shift+V` is that the text arrives as text. A
        // Fountain paste has already been classified by the parser, and
        // re-classifying the seam is what makes the block it landed in agree
        // with the blocks it landed between.
        if plain {
            outcome(session, result)
        } else {
            inferring(session, Some(at), result)
        }
    })
}

#[frb(sync)]
pub fn doc_undo(handle: DocumentHandle) -> Option<EditResult> {
    step(handle, model::Document::undo)
}

#[frb(sync)]
pub fn doc_redo(handle: DocumentHandle) -> Option<EditResult> {
    step(handle, model::Document::redo)
}

fn step(
    handle: DocumentHandle,
    take: fn(&mut model::Document) -> Option<model::EditResult>,
) -> Option<EditResult> {
    actor().run(move |state| {
        let session = state.session_mut(handle.id)?;
        // Undo ends the run of typing it is undoing, so the next keystroke
        // starts a transaction of its own rather than reopening the old one.
        let result = take(session.interrupt())?;
        // An undo is an edit. A crash after one must not bring back the text it
        // took away, so it goes in the journal like everything else.
        journal(session, &result);
        Some(result_view(session.document(), result))
    })
}

// ---------------------------------------------------------------------------
// Enter and Tab
// ---------------------------------------------------------------------------

/// Enter, as a plan the document runs in one transaction.
///
/// Three cases, and the middle one is the whole of §Phase 3's table:
///
/// * **A selection.** It goes first, and everything below happens where it was.
/// * **The caret at the end of a block.** The block splits and the new block
///   below it takes the kind the table says follows this one, unforced — it is
///   empty, so there is nothing to pin yet, and leaving it open is what lets
///   `INT.` typed into it be recognised.
/// * **The caret inside a block.** The split is breaking one element in two, so
///   both halves stay what they were, kind and `forced` included. Pressing Enter
///   in the middle of an action paragraph does not turn its second half into
///   something else.
fn enter(group: &mut model::Grouped<'_>, at: model::DocSelection) -> Result<(), model::EditError> {
    let (from, to) = ordered(group.document(), at);
    if from != to {
        group.apply(model::EditCommand::DeleteRange { from, to })?;
    }
    let block = from.block;

    let (kind, forced, at_end, cue) = {
        let document = group.document();
        let index = document
            .index_of(block)
            .ok_or(model::EditError::UnknownBlock(block))?;
        let current = &document.blocks()[index];
        let previous = index
            .checked_sub(1)
            .map(|earlier| document.blocks()[earlier].kind());
        (
            current.kind(),
            current.forced(),
            from.offset as usize == current.text().len(),
            model::enter_makes_a_cue(current.kind(), current.forced(), current.text(), previous),
        )
    };

    // Enter a second time at the end of a speech: the empty paragraph the first
    // one left becomes the cue the writer is plainly reaching for, rather than a
    // second empty paragraph under it.
    if cue {
        return group
            .apply(model::EditCommand::SetKind {
                block,
                kind: model::BlockKind::Character,
                forced: true,
            })
            .map(drop);
    }

    let split = group.apply(model::EditCommand::SplitBlock {
        block,
        at: from.offset,
    })?;
    let Some(created) = split.inserted.first().copied() else {
        return Ok(());
    };
    if !at_end {
        return Ok(());
    }
    let wanted = model::kind_after_enter(kind);
    if (wanted, false) != (kind, forced) {
        group.apply(model::EditCommand::SetKind {
            block: created,
            kind: wanted,
            forced: false,
        })?;
    }
    Ok(())
}

/// The kind Tab (or Shift+Tab) moves `block` to, from `document`'s table.
fn tab_target(
    document: &model::Document,
    block: model::BlockId,
    shift: bool,
) -> Option<model::BlockKind> {
    let index = document.index_of(block)?;
    let blocks = document.blocks();
    let current = blocks[index].kind();
    if shift {
        let previous = index.checked_sub(1).map(|earlier| blocks[earlier].kind());
        model::kind_before_tab(current, previous)
    } else {
        model::kind_after_tab(current)
    }
    .filter(|target| *target != current)
}

// ---------------------------------------------------------------------------
// Paste
// ---------------------------------------------------------------------------

/// Splits plain text into Action blocks, one per line.
///
/// `forced` stays false: the serialiser already adds `!` to any line that would
/// otherwise be read back as something else, so a pasted `INT. HOUSE - DAY`
/// stays Action without the file gaining a marker it does not need.
fn plain_blocks(text: &str) -> Vec<model::NewBlock> {
    text.split('\n')
        .map(|line| line.strip_suffix('\r').unwrap_or(line))
        // A blank line is a separator in Fountain, and an empty block has no
        // representation at all (ADR 0007) — dropping them here loses nothing.
        .filter(|line| !line.trim().is_empty())
        .map(|line| model::NewBlock::new(model::BlockKind::Action, line))
        .collect()
}

/// The paste itself, as a plan the document runs in one transaction.
///
/// Where the caret is decides the shape, and the three cases are the three
/// things a writer can mean:
///
/// * **Inside a block.** The text is spliced in: the first pasted block joins
///   what precedes the caret, the last joins what follows it, and anything
///   between them becomes blocks of its own. This is what every text editor
///   does, and for a single pasted block it is the only sensible reading.
/// * **At a block boundary**, with more than one block to paste. The blocks go
///   in whole, before or after the block the caret is in. Appending a copied
///   scene heading onto the end of a line of dialogue is never what was meant.
/// * **Into an empty block.** The first pasted block fills it, kind and all,
///   which is what makes "copy a scene, paste it into a new script" produce a
///   scene rather than a scene under a stray blank.
fn paste(
    group: &mut model::Grouped<'_>,
    at: model::DocSelection,
    blocks: Vec<model::NewBlock>,
) -> Result<(), model::EditError> {
    let (from, to) = ordered(group.document(), at);
    let head_is_empty = from.offset == 0;
    let tail_is_empty = group
        .document()
        .block(to.block)
        .is_some_and(|block| to.offset as usize == block.text().len());

    if from != to {
        group.apply(model::EditCommand::DeleteRange { from, to })?;
    }
    let mut blocks = blocks.into_iter();
    let Some(first) = blocks.next() else {
        return Ok(());
    };
    let mut rest: Vec<model::NewBlock> = blocks.collect();
    let block_is_empty = head_is_empty && tail_is_empty;

    // Whole blocks at a boundary. Not for a single block: pasting one word at
    // the end of a line is text, whatever kind the word was copied from.
    if !rest.is_empty() && !block_is_empty && (head_is_empty || tail_is_empty) {
        let index = group
            .document()
            .index_of(from.block)
            .ok_or(model::EditError::UnknownBlock(from.block))?;
        let after = if tail_is_empty {
            Some(from.block)
        } else {
            // Before the caret's block is after the one before it, and `None`
            // when there is nothing before it at all.
            index
                .checked_sub(1)
                .map(|previous| group.document().blocks()[previous].id())
        };
        let mut all = vec![first];
        all.append(&mut rest);
        group.apply(model::EditCommand::InsertBlocks { after, blocks: all })?;
        return Ok(());
    }

    // The first pasted block's text lands in the block the caret is in.
    if !first.text.is_empty() {
        group.apply(model::EditCommand::ReplaceText {
            block: from.block,
            range: from.offset..from.offset,
            with: first.text.clone(),
        })?;
    }
    // Its *kind* lands there only when the block had nothing to disagree with.
    if block_is_empty {
        adopt(group, from.block, &first)?;
    }
    if rest.is_empty() {
        return Ok(());
    }

    // Everything after the first goes below. The text that was after the caret
    // is carried past it, in a block of its own, so it ends up after the pasted
    // content rather than inside it.
    let tail = if tail_is_empty {
        None
    } else {
        let split = group.apply(model::EditCommand::SplitBlock {
            block: from.block,
            at: from.offset + clamp_u32(first.text.len()),
        })?;
        Some(split.inserted[0])
    };
    // With a tail to join, the last pasted block merges into it rather than
    // becoming a block of its own — the mirror image of what `first` just did.
    let last = tail.and_then(|_| rest.pop());

    if !rest.is_empty() {
        group.apply(model::EditCommand::InsertBlocks {
            after: Some(from.block),
            blocks: rest,
        })?;
    }
    if let (Some(tail), Some(last)) = (tail, last) {
        if !last.text.is_empty() {
            group.apply(model::EditCommand::ReplaceText {
                block: tail,
                range: 0..0,
                with: last.text,
            })?;
        }
    }
    Ok(())
}

/// Gives a block the kind of the block being pasted into it.
///
/// Plain unforced Action is the kind that *typed* text has, and inserting text
/// over a selection comes through here as a paste so that it stays one undo
/// step. Adopting it would silently demote a scene heading whose text the user
/// selected and retyped, so it is the one kind that never travels.
fn adopt(
    group: &mut model::Grouped<'_>,
    block: model::BlockId,
    new: &model::NewBlock,
) -> Result<(), model::EditError> {
    if new.kind == model::BlockKind::Action && !new.forced {
        return Ok(());
    }
    if group
        .document()
        .block(block)
        .is_some_and(|existing| existing.kind() == new.kind && existing.forced() == new.forced)
    {
        return Ok(());
    }
    group.apply(model::EditCommand::SetKind {
        block,
        kind: new.kind,
        forced: new.forced,
    })?;
    if new.dual {
        group.apply(model::EditCommand::SetDual { block, dual: true })?;
    }
    Ok(())
}

// ---------------------------------------------------------------------------
// Conversion — the only direction-changing code in the surface
// ---------------------------------------------------------------------------

fn view_of(block: &model::Block) -> BlockView {
    let (kind, section_level) = kind_view(block.kind());
    BlockView {
        id: block.id().0,
        kind,
        section_level,
        text: block.text().to_owned(),
        forced: block.forced(),
        dual: block.dual(),
        read_only: block.kind() == model::BlockKind::Opaque,
    }
}

fn kind_view(kind: model::BlockKind) -> (BlockKind, u8) {
    match kind {
        model::BlockKind::SceneHeading => (BlockKind::SceneHeading, 0),
        model::BlockKind::Action => (BlockKind::Action, 0),
        model::BlockKind::Character => (BlockKind::Character, 0),
        model::BlockKind::Dialogue => (BlockKind::Dialogue, 0),
        model::BlockKind::Parenthetical => (BlockKind::Parenthetical, 0),
        model::BlockKind::Transition => (BlockKind::Transition, 0),
        model::BlockKind::Centered => (BlockKind::Centered, 0),
        model::BlockKind::Lyric => (BlockKind::Lyric, 0),
        model::BlockKind::Section { level } => (BlockKind::Section, level),
        model::BlockKind::Synopsis => (BlockKind::Synopsis, 0),
        model::BlockKind::Note => (BlockKind::Note, 0),
        model::BlockKind::PageBreak => (BlockKind::PageBreak, 0),
        model::BlockKind::Opaque => (BlockKind::Opaque, 0),
    }
}

fn model_kind(kind: BlockKind, section_level: u8) -> model::BlockKind {
    match kind {
        BlockKind::SceneHeading => model::BlockKind::SceneHeading,
        BlockKind::Action => model::BlockKind::Action,
        BlockKind::Character => model::BlockKind::Character,
        BlockKind::Dialogue => model::BlockKind::Dialogue,
        BlockKind::Parenthetical => model::BlockKind::Parenthetical,
        BlockKind::Transition => model::BlockKind::Transition,
        BlockKind::Centered => model::BlockKind::Centered,
        BlockKind::Lyric => model::BlockKind::Lyric,
        BlockKind::Section => model::BlockKind::Section {
            // A level Dart cannot express is a level the model rejects, so it is
            // pinned to the range §4.1 allows rather than refused.
            level: section_level.clamp(1, 6),
        },
        BlockKind::Synopsis => model::BlockKind::Synopsis,
        BlockKind::Note => model::BlockKind::Note,
        BlockKind::PageBreak => model::BlockKind::PageBreak,
        BlockKind::Opaque => model::BlockKind::Opaque,
    }
}

/// Converts a UTF-16 offset into the byte offset the model uses, against the
/// text of the block it points into (§2.4).
fn to_model_position(
    document: &model::Document,
    position: DocPosition,
) -> Result<model::DocPosition, EditOutcome> {
    let id = model::BlockId(position.block);
    let block = document
        .block(id)
        .ok_or_else(|| rejected(EditRejection::UnknownBlock, format!("no block {}", id.0)))?;
    let offset = offsets::utf16_to_utf8(block.text(), position.offset_utf16).ok_or_else(|| {
        rejected(
            EditRejection::BadUtf16Offset,
            format!(
                "utf-16 offset {} is not a boundary in block {}",
                position.offset_utf16, id.0
            ),
        )
    })?;
    Ok(model::DocPosition::new(id, clamp_u32(offset)))
}

fn to_model_selection(
    document: &model::Document,
    selection: Option<DocSelection>,
) -> Result<Option<model::DocSelection>, EditOutcome> {
    match selection {
        None => Ok(None),
        Some(selection) => Ok(Some(model::DocSelection {
            anchor: to_model_position(document, selection.anchor)?,
            focus: to_model_position(document, selection.focus)?,
        })),
    }
}

fn to_model_command(
    document: &model::Document,
    command: EditCommand,
) -> Result<model::EditCommand, EditOutcome> {
    Ok(match command {
        EditCommand::ReplaceText {
            block,
            start_utf16,
            end_utf16,
            with,
        } => {
            let start = to_model_position(
                document,
                DocPosition {
                    block,
                    offset_utf16: start_utf16,
                },
            )?;
            let end = to_model_position(
                document,
                DocPosition {
                    block,
                    offset_utf16: end_utf16,
                },
            )?;
            model::EditCommand::ReplaceText {
                block: start.block,
                range: start.offset..end.offset,
                with,
            }
        }
        EditCommand::SplitBlock { block, at_utf16 } => {
            let at = to_model_position(
                document,
                DocPosition {
                    block,
                    offset_utf16: at_utf16,
                },
            )?;
            model::EditCommand::SplitBlock {
                block: at.block,
                at: at.offset,
            }
        }
        EditCommand::MergeBlocks { first } => model::EditCommand::MergeBlocks {
            first: model::BlockId(first),
        },
        EditCommand::SetKind {
            block,
            kind,
            section_level,
            forced,
        } => model::EditCommand::SetKind {
            block: model::BlockId(block),
            kind: model_kind(kind, section_level),
            forced,
        },
        EditCommand::InsertBlocks { after, blocks } => model::EditCommand::InsertBlocks {
            after: after.map(model::BlockId),
            blocks: blocks.into_iter().map(model_new_block).collect(),
        },
        EditCommand::DeleteRange { from, to } => model::EditCommand::DeleteRange {
            from: to_model_position(document, from)?,
            to: to_model_position(document, to)?,
        },
        EditCommand::SetDual { block, dual } => model::EditCommand::SetDual {
            block: model::BlockId(block),
            dual,
        },
    })
}

fn model_new_block(block: NewBlock) -> model::NewBlock {
    model::NewBlock {
        kind: model_kind(block.kind, block.section_level),
        text: block.text,
        forced: block.forced,
        dual: block.dual,
    }
}

/// Reads a selection back in document order, so a plan does not have to care
/// which way the user dragged.
fn ordered(
    document: &model::Document,
    selection: model::DocSelection,
) -> (model::DocPosition, model::DocPosition) {
    let anchor = document.index_of(selection.anchor.block);
    let focus = document.index_of(selection.focus.block);
    if (anchor, selection.anchor.offset) <= (focus, selection.focus.offset) {
        (selection.anchor, selection.focus)
    } else {
        (selection.focus, selection.anchor)
    }
}

fn position_view(document: &model::Document, position: model::DocPosition) -> Option<DocPosition> {
    let block = document.block(position.block)?;
    Some(DocPosition {
        block: position.block.0,
        offset_utf16: offsets::utf8_to_utf16(block.text(), position.offset as usize)?,
    })
}

fn selection_view(
    document: &model::Document,
    selection: Option<model::DocSelection>,
) -> Option<DocSelection> {
    let selection = selection?;
    Some(DocSelection {
        anchor: position_view(document, selection.anchor)?,
        focus: position_view(document, selection.focus)?,
    })
}

fn result_view(document: &model::Document, result: model::EditResult) -> EditResult {
    let blocks = document.blocks();
    EditResult {
        changed: result
            .changed
            .iter()
            .filter_map(|id| document.block(*id))
            .map(view_of)
            .collect(),
        removed: result.removed.iter().map(|id| id.0).collect(),
        inserted: {
            let mut inserted: Vec<InsertedBlock> = result
                .inserted
                .iter()
                .filter_map(|id| {
                    let index = document.index_of(*id)?;
                    Some(InsertedBlock {
                        index: clamp_u32(index),
                        block: view_of(&blocks[index]),
                    })
                })
                .collect();
            // Ascending, so applying them in order lands each at its own index.
            inserted.sort_by_key(|block| block.index);
            inserted
        },
        selection: selection_view(document, result.selection),
        block_count: clamp_u32(blocks.len()),
    }
}

/// Turns whichever way an edit went into an [`EditOutcome`], and writes what it
/// did to the crash journal.
///
/// Every mutation in this module ends here or in [`inferring`], which is the
/// whole reason the journal can claim to hold every edit: there is no path from
/// Dart to the document that does not pass through one of these two functions.
fn outcome(
    session: &mut Session,
    result: Result<model::EditResult, model::EditError>,
) -> EditOutcome {
    match result {
        Ok(result) => {
            journal(session, &result);
            EditOutcome::Applied {
                result: result_view(session.document(), result),
            }
        }
        Err(error) => rejected(rejection_of(&error), error.to_string()),
    }
}

/// Appends what an edit did to the session's journal (§Phase 4).
///
/// The patch records the **outcome** — the blocks as they now stand — rather
/// than the command, so replaying it needs none of the inference or workflow
/// rules that produced it. See `document::recovery`.
///
/// This runs after `reinfer`, so the kinds it records are the kinds the writer
/// is looking at.
fn journal(session: &mut Session, result: &model::EditResult) {
    let document = session.document();
    let mut inserted: Vec<(u32, model::BlockSnapshot)> = result
        .inserted
        .iter()
        .filter_map(|id| Some((clamp_u32(document.index_of(*id)?), document.snapshot(*id)?)))
        .collect();
    inserted.sort_by_key(|(index, _)| *index);
    let patch = model::Patch {
        removed: result.removed.clone(),
        changed: result
            .changed
            .iter()
            .filter_map(|id| document.snapshot(*id))
            .collect(),
        inserted,
    };
    if session.record(&patch) {
        // Said once, not once per keystroke.
        emit(CoreEvent::JournalBroken {
            handle: session.handle(),
        });
    }
}

/// The same, with §4.2's automatic re-classification applied to whatever the
/// edit disturbed.
///
/// Every ordinary keystroke comes through here. `document` decides the scope —
/// one block either side, nothing forced, nothing far from the caret — and folds
/// the kinds it changed into the patch, so Dart applies one patch and does not
/// have to know that anything reclassified at all.
fn inferring(
    session: &mut Session,
    before: Option<model::DocSelection>,
    result: Result<model::EditResult, model::EditError>,
) -> EditOutcome {
    match result {
        Ok(mut result) => {
            session.document_mut().reinfer(&mut result, before);
            journal(session, &result);
            EditOutcome::Applied {
                result: result_view(session.document(), result),
            }
        }
        Err(error) => rejected(rejection_of(&error), error.to_string()),
    }
}

fn model_query(query: FindQuery) -> model::FindQuery {
    model::FindQuery {
        text: query.text,
        case_sensitive: query.case_sensitive,
        whole_word: query.whole_word,
        // A `Section` from Dart carries no level (ADR 0009), and a filter that
        // matched only level 1 would silently miss the rest.
        kinds: query
            .kinds
            .into_iter()
            .flat_map(|kind| match kind {
                BlockKind::Section => (1..=6)
                    .map(|level| model::BlockKind::Section { level })
                    .collect(),
                other => vec![model_kind(other, 0)],
            })
            .collect(),
    }
}

fn match_view(document: &model::Document, hit: &model::Match) -> Option<FindMatch> {
    let text = document.block(hit.block)?.text();
    Some(FindMatch {
        block: hit.block.0,
        start_utf16: offsets::utf8_to_utf16(text, hit.range.start as usize)?,
        end_utf16: offsets::utf8_to_utf16(text, hit.range.end as usize)?,
    })
}

fn rejection_of(error: &model::EditError) -> EditRejection {
    match error {
        model::EditError::UnknownBlock(_) => EditRejection::UnknownBlock,
        model::EditError::BadOffset { .. } => EditRejection::BadOffset,
        model::EditError::NoBlockAfter(_) => EditRejection::NoBlockAfter,
        model::EditError::BadRange => EditRejection::BadRange,
        model::EditError::NotEditable(_) => EditRejection::NotEditable,
        model::EditError::InvalidBlock { .. } => EditRejection::InvalidBlock,
    }
}

fn rejected(reason: EditRejection, message: String) -> EditOutcome {
    EditOutcome::Rejected { reason, message }
}

fn no_such_document() -> EditOutcome {
    rejected(
        EditRejection::NoSuchDocument,
        "no document with that handle".to_owned(),
    )
}

/// Offsets are `u32` across the bridge (§3.4); saturating beats wrapping into a
/// small, plausible-looking, catastrophically wrong number.
fn clamp_u32(value: usize) -> u32 {
    u32::try_from(value).unwrap_or(u32::MAX)
}

#[cfg(test)]
mod tests {
    use super::*;

    const SCRIPT: &str = "INT. HOUSE - DAY\n\nJohn enters.\n\nJOHN\n(quietly)\nHello.\n";

    /// A line with one character from every width class the offset conversion
    /// has to get right: ASCII, a Latin-1 accent, CJK, and a surrogate pair.
    const MIXED: &str = "aé日🎬";

    struct Doc(DocumentHandle);

    impl Doc {
        fn parse(source: &str) -> Doc {
            Doc(doc_parse(source.to_owned()))
        }

        fn new() -> Doc {
            Doc(doc_new())
        }

        fn handle(&self) -> DocumentHandle {
            self.0
        }

        fn blocks(&self) -> Vec<BlockView> {
            doc_blocks(self.0, 0, u32::MAX)
        }

        fn id(&self, index: usize) -> u64 {
            self.blocks()[index].id
        }

        fn text(&self) -> String {
            doc_source(self.0)
        }

        fn apply(&self, command: EditCommand) -> EditResult {
            match doc_apply(self.0, command, None) {
                EditOutcome::Applied { result } => result,
                EditOutcome::Rejected { reason, message } => {
                    panic!("expected the edit to apply: {reason:?} — {message}")
                }
            }
        }

        fn reject(&self, command: EditCommand) -> EditRejection {
            match doc_apply(self.0, command, None) {
                EditOutcome::Applied { .. } => panic!("expected the edit to be refused"),
                EditOutcome::Rejected { reason, .. } => reason,
            }
        }

        fn kinds(&self) -> Vec<BlockKind> {
            self.blocks().into_iter().map(|block| block.kind).collect()
        }

        fn caret(&self, index: usize, offset_utf16: u32) -> DocSelection {
            let at = DocPosition {
                block: self.id(index),
                offset_utf16,
            };
            DocSelection {
                anchor: at,
                focus: at,
            }
        }

        /// The caret at the end of a block, where a writer presses Enter.
        fn end_of(&self, index: usize) -> DocSelection {
            let block = &self.blocks()[index];
            self.caret(index, block.text.len() as u32)
        }

        /// Types `text` a character at a time, as the surface does.
        fn types(&self, index: usize, text: &str) {
            let id = self.id(index);
            for character in text.chars() {
                let offset = self
                    .blocks()
                    .iter()
                    .find(|block| block.id == id)
                    .map(|block| block.text.len() as u32)
                    .expect("the block is still there");
                let at = DocPosition {
                    block: id,
                    offset_utf16: offset,
                };
                let before = DocSelection {
                    anchor: at,
                    focus: at,
                };
                match doc_apply(
                    self.0,
                    EditCommand::ReplaceText {
                        block: id,
                        start_utf16: offset,
                        end_utf16: offset,
                        with: character.to_string(),
                    },
                    Some(before),
                ) {
                    EditOutcome::Applied { .. } => {}
                    EditOutcome::Rejected { reason, message } => {
                        panic!("typing {character:?} was refused: {reason:?} — {message}")
                    }
                }
            }
        }

        fn enter(&self, at: DocSelection) -> EditResult {
            match doc_enter(self.0, at) {
                EditOutcome::Applied { result } => result,
                EditOutcome::Rejected { reason, message } => {
                    panic!("expected Enter to apply: {reason:?} — {message}")
                }
            }
        }

        fn tab(&self, at: DocSelection, shift: bool) -> Option<EditResult> {
            match doc_tab(self.0, at, shift) {
                None => None,
                Some(EditOutcome::Applied { result }) => Some(result),
                Some(EditOutcome::Rejected { reason, message }) => {
                    panic!("expected Tab to apply: {reason:?} — {message}")
                }
            }
        }
    }

    impl Drop for Doc {
        fn drop(&mut self) {
            doc_close(self.0);
        }
    }

    #[test]
    fn a_new_script_has_one_empty_block() {
        let doc = Doc::new();
        assert_eq!(doc_block_count(doc.handle()), 1);
        let blocks = doc.blocks();
        assert_eq!(blocks[0].kind, BlockKind::Action);
        assert!(blocks[0].text.is_empty());
        assert!(!blocks[0].read_only);
        assert_eq!(doc.text(), "");
    }

    #[test]
    fn parsing_reports_every_element_with_its_kind() {
        let doc = Doc::parse(SCRIPT);
        assert_eq!(doc_block_count(doc.handle()), 5);
        assert_eq!(
            doc.kinds(),
            [
                BlockKind::SceneHeading,
                BlockKind::Action,
                BlockKind::Character,
                BlockKind::Parenthetical,
                BlockKind::Dialogue,
            ]
        );
        assert_eq!(doc.text(), SCRIPT, "an untouched document round-trips");
    }

    #[test]
    fn a_section_carries_its_level_beside_its_kind() {
        let doc = Doc::parse("### Act Three\n");
        let block = &doc.blocks()[0];
        assert_eq!(block.kind, BlockKind::Section);
        assert_eq!(block.section_level, 3);
        assert_eq!(block.text, "Act Three");
    }

    #[test]
    fn a_boneyard_comment_is_read_only() {
        let doc = Doc::parse("/* hidden */\n");
        let block = &doc.blocks()[0];
        assert_eq!(block.kind, BlockKind::Opaque);
        assert!(block.read_only);
        assert_eq!(
            doc.reject(EditCommand::ReplaceText {
                block: block.id,
                start_utf16: 0,
                end_utf16: 0,
                with: "x".to_owned(),
            }),
            EditRejection::NotEditable
        );
    }

    #[test]
    fn a_block_range_is_clamped_rather_than_refused() {
        let doc = Doc::parse(SCRIPT);
        assert_eq!(doc_blocks(doc.handle(), 3, 99).len(), 2);
        assert_eq!(doc_blocks(doc.handle(), 99, 120).len(), 0);
        assert_eq!(doc_blocks(doc.handle(), 4, 2).len(), 0);
    }

    #[test]
    fn a_stale_handle_answers_rather_than_panics() {
        let handle = doc_new();
        doc_close(handle);
        assert_eq!(doc_block_count(handle), 0);
        assert!(doc_blocks(handle, 0, 10).is_empty());
        assert_eq!(doc_source(handle), "");
        assert!(doc_undo(handle).is_none());
        assert!(matches!(
            doc_apply(handle, EditCommand::MergeBlocks { first: 1 }, None),
            EditOutcome::Rejected {
                reason: EditRejection::NoSuchDocument,
                ..
            }
        ));
    }

    // --- offsets ---------------------------------------------------------

    #[test]
    fn edits_are_addressed_in_dart_coordinates() {
        let doc = Doc::parse(&format!("{MIXED}\n"));
        let id = doc.id(0);
        // UTF-16 offsets 1..2 are the accent: 1 unit, 2 bytes.
        doc.apply(EditCommand::ReplaceText {
            block: id,
            start_utf16: 1,
            end_utf16: 2,
            with: "e".to_owned(),
        });
        assert_eq!(doc.blocks()[0].text, "ae日🎬");
    }

    #[test]
    fn an_offset_inside_a_surrogate_pair_is_refused_not_rounded() {
        let doc = Doc::parse(&format!("{MIXED}\n"));
        let id = doc.id(0);
        // 3..5 is the emoji; 4 is between its halves.
        assert_eq!(
            doc.reject(EditCommand::ReplaceText {
                block: id,
                start_utf16: 3,
                end_utf16: 4,
                with: String::new(),
            }),
            EditRejection::BadUtf16Offset
        );
        assert_eq!(
            doc.reject(EditCommand::SplitBlock {
                block: id,
                at_utf16: 4
            }),
            EditRejection::BadUtf16Offset
        );
        assert_eq!(
            doc.reject(EditCommand::ReplaceText {
                block: id,
                start_utf16: 0,
                end_utf16: 99,
                with: String::new(),
            }),
            EditRejection::BadUtf16Offset
        );
        assert_eq!(doc.blocks()[0].text, MIXED, "and nothing changed");
    }

    #[test]
    fn the_caret_comes_back_in_dart_coordinates() {
        let doc = Doc::parse(&format!("{MIXED}\n"));
        let id = doc.id(0);
        let result = doc.apply(EditCommand::ReplaceText {
            block: id,
            start_utf16: 5,
            end_utf16: 5,
            with: "!".to_owned(),
        });
        let selection = result.selection.expect("a caret");
        // 'aé日🎬!' is 6 UTF-16 units and 11 bytes; Dart must be told 6.
        assert_eq!(selection.focus.offset_utf16, 6);
        assert_eq!(selection.anchor, selection.focus);
    }

    // --- patches ---------------------------------------------------------

    #[test]
    fn a_split_reports_the_new_block_and_where_it_went() {
        let doc = Doc::parse(SCRIPT);
        let id = doc.id(1);
        let result = doc.apply(EditCommand::SplitBlock {
            block: id,
            at_utf16: 5,
        });

        assert_eq!(result.changed.len(), 1);
        assert_eq!(result.changed[0].id, id);
        assert_eq!(result.changed[0].text, "John ");
        assert_eq!(result.inserted.len(), 1);
        assert_eq!(result.inserted[0].index, 2);
        assert_eq!(result.inserted[0].block.text, "enters.");
        assert_eq!(result.inserted[0].block.kind, BlockKind::Action);
        assert!(result.removed.is_empty());
        assert_eq!(result.block_count, 6);
        assert_eq!(
            result.selection.unwrap().focus.block,
            result.inserted[0].block.id
        );
    }

    #[test]
    fn a_cross_block_delete_reports_what_it_removed() {
        let doc = Doc::parse(SCRIPT);
        let result = doc.apply(EditCommand::DeleteRange {
            from: DocPosition {
                block: doc.id(1),
                offset_utf16: 4,
            },
            to: DocPosition {
                block: doc.id(4),
                offset_utf16: 2,
            },
        });

        assert_eq!(result.removed.len(), 3);
        assert_eq!(result.changed[0].text, "Johnllo.");
        assert_eq!(result.block_count, 2);
    }

    #[test]
    fn inserted_blocks_come_back_in_ascending_index_order() {
        let doc = Doc::parse(SCRIPT);
        let result = doc.apply(EditCommand::InsertBlocks {
            after: Some(doc.id(0)),
            blocks: vec![
                NewBlock {
                    kind: BlockKind::Action,
                    section_level: 0,
                    text: "One.".to_owned(),
                    forced: false,
                    dual: false,
                },
                NewBlock {
                    kind: BlockKind::Action,
                    section_level: 0,
                    text: "Two.".to_owned(),
                    forced: false,
                    dual: false,
                },
            ],
        });

        let indices: Vec<u32> = result.inserted.iter().map(|block| block.index).collect();
        assert_eq!(indices, [1, 2]);
        assert_eq!(result.inserted[0].block.text, "One.");
        assert_eq!(result.block_count, 7);
    }

    // --- history ---------------------------------------------------------

    #[test]
    fn undo_puts_the_caret_back_where_the_user_had_it() {
        let doc = Doc::parse("abcdef\n");
        let id = doc.id(0);
        let before = DocSelection {
            anchor: DocPosition {
                block: id,
                offset_utf16: 4,
            },
            focus: DocPosition {
                block: id,
                offset_utf16: 1,
            },
        };
        let applied = doc_apply(
            doc.handle(),
            EditCommand::ReplaceText {
                block: id,
                start_utf16: 1,
                end_utf16: 4,
                with: "X".to_owned(),
            },
            Some(before),
        );
        let EditOutcome::Applied { result: applied } = applied else {
            panic!("the edit applies");
        };

        let undone = doc_undo(doc.handle()).expect("something to undo");
        assert_eq!(undone.selection, Some(before), "direction included");
        assert_eq!(undone.changed[0].text, "abcdef");

        let redone = doc_redo(doc.handle()).expect("something to redo");
        assert_eq!(redone.selection, applied.selection);
        assert_eq!(redone.changed[0].text, "aXef");
    }

    #[test]
    fn undo_restores_deleted_blocks_at_their_old_positions() {
        let doc = Doc::parse(SCRIPT);
        let before: Vec<u64> = doc.blocks().iter().map(|block| block.id).collect();
        doc.apply(EditCommand::DeleteRange {
            from: DocPosition {
                block: before[1],
                offset_utf16: 0,
            },
            to: DocPosition {
                block: before[4],
                offset_utf16: 6,
            },
        });

        let undone = doc_undo(doc.handle()).expect("something to undo");
        let indices: Vec<u32> = undone.inserted.iter().map(|block| block.index).collect();
        assert_eq!(indices, [2, 3, 4]);
        assert_eq!(
            doc.blocks()
                .iter()
                .map(|block| block.id)
                .collect::<Vec<_>>(),
            before
        );
        assert_eq!(doc.text(), SCRIPT);
    }

    #[test]
    fn a_run_of_typing_is_one_undo_step() {
        let doc = Doc::parse("abc\n");
        let id = doc.id(0);
        for offset in 0..3u32 {
            doc.apply(EditCommand::ReplaceText {
                block: id,
                start_utf16: offset,
                end_utf16: offset,
                with: "x".to_owned(),
            });
        }
        assert_eq!(doc.blocks()[0].text, "xxxabc");

        doc_undo(doc.handle()).expect("something to undo");
        assert_eq!(doc.blocks()[0].text, "abc");
        assert!(doc_undo(doc.handle()).is_none());
    }

    // --- clipboard -------------------------------------------------------

    #[test]
    fn extracting_a_selection_gives_fountain_back() {
        let doc = Doc::parse(SCRIPT);
        let text = doc_extract(
            doc.handle(),
            DocPosition {
                block: doc.id(2),
                offset_utf16: 0,
            },
            DocPosition {
                block: doc.id(4),
                offset_utf16: 6,
            },
        );
        assert_eq!(text.as_deref(), Some("JOHN\n(quietly)\nHello.\n"));

        let inside = doc_extract(
            doc.handle(),
            DocPosition {
                block: doc.id(1),
                offset_utf16: 0,
            },
            DocPosition {
                block: doc.id(1),
                offset_utf16: 4,
            },
        );
        assert_eq!(inside.as_deref(), Some("John"), "inside a block it is text");
    }

    #[test]
    fn extracting_with_a_broken_offset_answers_none() {
        let doc = Doc::parse(&format!("{MIXED}\n"));
        let id = doc.id(0);
        assert_eq!(
            doc_extract(
                doc.handle(),
                DocPosition {
                    block: id,
                    offset_utf16: 0
                },
                DocPosition {
                    block: id,
                    offset_utf16: 4
                },
            ),
            None
        );
    }

    #[test]
    fn pasting_one_block_inserts_its_text_at_the_caret() {
        let doc = Doc::parse(SCRIPT);
        let id = doc.id(1);
        let caret = DocSelection {
            anchor: DocPosition {
                block: id,
                offset_utf16: 4,
            },
            focus: DocPosition {
                block: id,
                offset_utf16: 4,
            },
        };
        let EditOutcome::Applied { result } =
            doc_paste(doc.handle(), caret, " quickly".to_owned(), false)
        else {
            panic!("the paste applies");
        };

        assert_eq!(doc.blocks()[1].text, "John quickly enters.");
        assert_eq!(result.block_count, 5, "no block was created");
        assert_eq!(result.selection.unwrap().focus.offset_utf16, 12);
    }

    #[test]
    fn pasting_into_an_empty_block_adopts_its_kind() {
        let doc = Doc::new();
        let caret = DocSelection {
            anchor: DocPosition {
                block: doc.id(0),
                offset_utf16: 0,
            },
            focus: DocPosition {
                block: doc.id(0),
                offset_utf16: 0,
            },
        };
        doc_paste(doc.handle(), caret, "INT. HOUSE - DAY".to_owned(), false);

        assert_eq!(doc.kinds(), [BlockKind::SceneHeading]);
        assert_eq!(doc.text(), "INT. HOUSE - DAY\n");
    }

    #[test]
    fn pasting_several_blocks_carries_the_tail_past_them() {
        // The caret sits between "before" and "after", and the pasted text is
        // spliced in exactly there — the first pasted block joins what precedes
        // the caret and the last joins what follows it, with no space invented.
        let doc = Doc::parse("beforeafter.\n");
        let id = doc.id(0);
        let caret = DocSelection {
            anchor: DocPosition {
                block: id,
                offset_utf16: 6,
            },
            focus: DocPosition {
                block: id,
                offset_utf16: 6,
            },
        };
        doc_paste(
            doc.handle(),
            caret,
            "one\n\nINT. HOUSE - DAY\n\ntwo".to_owned(),
            false,
        );

        let blocks = doc.blocks();
        let texts: Vec<&str> = blocks.iter().map(|block| block.text.as_str()).collect();
        assert_eq!(texts, ["beforeone", "INT. HOUSE - DAY", "twoafter."]);
        assert_eq!(
            doc.kinds(),
            [
                BlockKind::Action,
                BlockKind::SceneHeading,
                BlockKind::Action
            ]
        );
    }

    #[test]
    fn pasting_whole_blocks_at_a_block_boundary_keeps_them_whole() {
        // A copied scene pasted at the end of a line of dialogue belongs after
        // that line, not welded onto the end of it.
        let doc = Doc::parse(SCRIPT);
        let last = doc.blocks().pop().expect("a last block");
        let caret = DocSelection {
            anchor: DocPosition {
                block: last.id,
                offset_utf16: last.text.len() as u32,
            },
            focus: DocPosition {
                block: last.id,
                offset_utf16: last.text.len() as u32,
            },
        };
        doc_paste(
            doc.handle(),
            caret,
            "INT. ROAD - NIGHT\n\nShe drives.".to_owned(),
            false,
        );

        assert_eq!(
            doc.kinds(),
            [
                BlockKind::SceneHeading,
                BlockKind::Action,
                BlockKind::Character,
                BlockKind::Parenthetical,
                BlockKind::Dialogue,
                BlockKind::SceneHeading,
                BlockKind::Action,
            ]
        );
        assert_eq!(doc.blocks()[4].text, "Hello.", "the dialogue is untouched");
    }

    #[test]
    fn pasting_whole_blocks_at_the_start_of_a_block_puts_them_above_it() {
        let doc = Doc::parse("JOHN\nHello.\n");
        let first = doc.id(0);
        let caret = DocSelection {
            anchor: DocPosition {
                block: first,
                offset_utf16: 0,
            },
            focus: DocPosition {
                block: first,
                offset_utf16: 0,
            },
        };
        doc_paste(
            doc.handle(),
            caret,
            "INT. ROAD - NIGHT\n\nShe drives.".to_owned(),
            false,
        );

        assert_eq!(
            doc.kinds(),
            [
                BlockKind::SceneHeading,
                BlockKind::Action,
                BlockKind::Character,
                BlockKind::Dialogue,
            ]
        );
    }

    #[test]
    fn pasting_one_block_at_a_boundary_is_still_text() {
        // The boundary rule is for several blocks. One word pasted at the end of
        // a line is a word, whatever it was copied from.
        let doc = Doc::parse("John enters\n");
        let id = doc.id(0);
        let caret = DocSelection {
            anchor: DocPosition {
                block: id,
                offset_utf16: 11,
            },
            focus: DocPosition {
                block: id,
                offset_utf16: 11,
            },
        };
        doc_paste(doc.handle(), caret, " slowly.".to_owned(), false);

        assert_eq!(doc.blocks().len(), 1);
        assert_eq!(doc.blocks()[0].text, "John enters slowly.");
    }

    #[test]
    fn pasting_replaces_the_selection_in_one_undo_step() {
        let doc = Doc::parse(SCRIPT);
        let selection = DocSelection {
            anchor: DocPosition {
                block: doc.id(1),
                offset_utf16: 0,
            },
            focus: DocPosition {
                block: doc.id(4),
                offset_utf16: 6,
            },
        };
        doc_paste(doc.handle(), selection, "MARY\nHi.".to_owned(), false);
        assert_eq!(
            doc.kinds(),
            [
                BlockKind::SceneHeading,
                BlockKind::Character,
                BlockKind::Dialogue
            ]
        );

        doc_undo(doc.handle()).expect("one step takes all of it back");
        assert_eq!(doc.text(), SCRIPT);
    }

    #[test]
    fn a_plain_paste_infers_nothing() {
        let doc = Doc::new();
        let caret = DocSelection {
            anchor: DocPosition {
                block: doc.id(0),
                offset_utf16: 0,
            },
            focus: DocPosition {
                block: doc.id(0),
                offset_utf16: 0,
            },
        };
        doc_paste(
            doc.handle(),
            caret,
            "INT. HOUSE - DAY\nCUT TO:".to_owned(),
            true,
        );

        assert_eq!(doc.kinds(), [BlockKind::Action, BlockKind::Action]);
        let texts: Vec<String> = doc.blocks().into_iter().map(|block| block.text).collect();
        assert_eq!(texts, ["INT. HOUSE - DAY", "CUT TO:"]);
        // …and the file it writes reads back the same way.
        assert_eq!(doc.text(), "!INT. HOUSE - DAY\n\n!CUT TO:\n");
        assert_eq!(
            Doc::parse(&doc.text()).kinds(),
            [BlockKind::Action, BlockKind::Action]
        );
    }

    #[test]
    fn typing_over_a_selection_never_changes_the_element_type() {
        // Selecting a whole scene heading and typing goes through the paste
        // path, so that it stays one undo step. What comes out must still be a
        // scene heading — the user is retyping the slug line, not demoting it.
        let doc = Doc::parse("INT. HOUSE - DAY\n\nAction.\n");
        let id = doc.id(0);
        let all = DocSelection {
            anchor: DocPosition {
                block: id,
                offset_utf16: 0,
            },
            focus: DocPosition {
                block: id,
                offset_utf16: 16,
            },
        };
        doc_paste(doc.handle(), all, "EXT. ROAD - NIGHT".to_owned(), true);

        assert_eq!(doc.kinds(), [BlockKind::SceneHeading, BlockKind::Action]);
        assert_eq!(doc.blocks()[0].text, "EXT. ROAD - NIGHT");
    }

    // --- automatic classification ----------------------------------------

    #[test]
    fn typing_a_slug_line_promotes_the_block_and_reports_it_in_the_patch() {
        let doc = Doc::new();
        let id = doc.id(0);
        doc.types(0, "INT. HOUSE");

        assert_eq!(doc.kinds(), [BlockKind::SceneHeading]);
        assert!(!doc.blocks()[0].forced, "inference never forces");
        // The last keystroke's patch has to carry the block, or the editor would
        // go on painting it as action.
        let EditOutcome::Applied { result } = doc_apply(
            doc.handle(),
            EditCommand::ReplaceText {
                block: id,
                start_utf16: 10,
                end_utf16: 10,
                with: " - DAY".to_owned(),
            },
            Some(doc.caret(0, 10)),
        ) else {
            panic!("the edit applies");
        };
        assert_eq!(result.changed.len(), 1);
        assert_eq!(result.changed[0].kind, BlockKind::SceneHeading);
        assert_eq!(doc.text(), "INT. HOUSE - DAY\n");
    }

    #[test]
    fn a_promotion_and_the_typing_that_caused_it_undo_together() {
        let doc = Doc::new();
        doc.types(0, "INT. HOUSE - DAY");
        doc_undo(doc.handle()).expect("something to undo");

        assert_eq!(doc.blocks()[0].text, "");
        assert_eq!(doc.kinds(), [BlockKind::Action]);
        assert!(
            doc_undo(doc.handle()).is_none(),
            "one run of typing, one undo step"
        );
    }

    #[test]
    fn an_element_shortcut_straight_after_a_promotion_wins() {
        // §Phase 3: "an immediate element-type shortcut after an automatic
        // change reverts and forces the user's choice".
        let doc = Doc::new();
        doc.types(0, "INT. HOUSE");
        assert_eq!(doc.kinds(), [BlockKind::SceneHeading]);

        doc.apply(EditCommand::SetKind {
            block: doc.id(0),
            kind: BlockKind::Action,
            section_level: 0,
            forced: true,
        });
        doc.types(0, " - DAY");

        assert_eq!(doc.kinds(), [BlockKind::Action]);
        assert_eq!(doc.blocks()[0].text, "INT. HOUSE - DAY");
        assert_eq!(doc.text(), "!INT. HOUSE - DAY\n");
    }

    #[test]
    fn a_plain_paste_still_infers_nothing_around_it() {
        let doc = Doc::new();
        doc_paste(
            doc.handle(),
            doc.caret(0, 0),
            "INT. HOUSE - DAY\nCUT TO:".to_owned(),
            true,
        );
        assert_eq!(doc.kinds(), [BlockKind::Action, BlockKind::Action]);
    }

    // --- Enter -----------------------------------------------------------

    /// §Phase 3's table, end to end through the bridge.
    #[test]
    fn enter_creates_the_element_the_table_says() {
        let rows = [
            (
                "INT. HOUSE - DAY\n",
                BlockKind::SceneHeading,
                BlockKind::Action,
            ),
            ("Action.\n", BlockKind::Action, BlockKind::Action),
            ("@JOHN\nHi.\n", BlockKind::Character, BlockKind::Dialogue),
            (
                "JOHN\n(quietly)\nHi.\n",
                BlockKind::Parenthetical,
                BlockKind::Dialogue,
            ),
            ("JOHN\nHello.\n", BlockKind::Dialogue, BlockKind::Action),
            (">CUT TO:\n", BlockKind::Transition, BlockKind::SceneHeading),
            ("~A lyric\n", BlockKind::Lyric, BlockKind::Lyric),
        ];
        for (source, from, expected) in rows {
            let doc = Doc::parse(source);
            let index = doc
                .kinds()
                .iter()
                .position(|kind| *kind == from)
                .unwrap_or_else(|| panic!("{source:?} has no {from:?} block"));
            let before = doc.blocks()[index].text.clone();

            let result = doc.enter(doc.end_of(index));

            assert_eq!(
                result.inserted.len(),
                1,
                "Enter in {from:?} should create one block"
            );
            let created = &result.inserted[0].block;
            assert_eq!(created.kind, expected, "Enter from {from:?}");
            assert!(created.text.is_empty());
            assert!(!created.forced, "a new empty block is not pinned");
            assert_eq!(
                doc.blocks()[index].text,
                before,
                "Enter never alters the text it was pressed in"
            );
            assert_eq!(
                result.selection.expect("a caret").focus.block,
                created.id,
                "the caret goes into the new block"
            );
        }
    }

    #[test]
    fn enter_a_second_time_after_a_speech_asks_for_a_cue() {
        let doc = Doc::parse("JOHN\nHello.\n");
        // Once: an action paragraph under the speech.
        let first = doc.enter(doc.end_of(1));
        let created = first.inserted[0].block.id;
        assert_eq!(first.inserted[0].block.kind, BlockKind::Action);

        // Twice: that empty paragraph becomes the next cue.
        let at = DocPosition {
            block: created,
            offset_utf16: 0,
        };
        let second = doc.enter(DocSelection {
            anchor: at,
            focus: at,
        });
        assert_eq!(second.block_count, 3, "no fourth block was created");
        assert_eq!(
            doc.kinds(),
            [
                BlockKind::Character,
                BlockKind::Dialogue,
                BlockKind::Character
            ]
        );
        assert!(doc.blocks()[2].forced, "the writer asked for a cue");
    }

    #[test]
    fn enter_in_the_middle_of_a_paragraph_leaves_both_halves_as_they_were() {
        let doc = Doc::parse("!INT. NOT A HEADING\n");
        assert!(doc.blocks()[0].forced);
        doc.enter(doc.caret(0, 5));

        let blocks = doc.blocks();
        assert_eq!(blocks[0].text, "INT. ");
        assert_eq!(blocks[1].text, "NOT A HEADING");
        assert_eq!(blocks[1].kind, BlockKind::Action);
        assert!(
            blocks[1].forced,
            "the second half is still the same element"
        );
    }

    #[test]
    fn enter_over_a_selection_replaces_it_in_one_undo_step() {
        let doc = Doc::parse(SCRIPT);
        let selection = DocSelection {
            anchor: DocPosition {
                block: doc.id(1),
                offset_utf16: 4,
            },
            focus: DocPosition {
                block: doc.id(4),
                offset_utf16: 2,
            },
        };
        doc.enter(selection);
        assert_eq!(doc.blocks()[1].text, "John");

        doc_undo(doc.handle()).expect("one step takes all of it back");
        assert_eq!(doc.text(), SCRIPT);
    }

    #[test]
    fn enter_in_a_read_only_block_is_refused() {
        let doc = Doc::parse("/* hidden */\n");
        assert!(matches!(
            doc_enter(doc.handle(), doc.end_of(0)),
            EditOutcome::Rejected {
                reason: EditRejection::NotEditable,
                ..
            }
        ));
        assert_eq!(doc.text(), "/* hidden */\n");
    }

    // --- Tab -------------------------------------------------------------

    /// The Tab half of §Phase 3's table, and its reverse.
    #[test]
    fn tab_and_shift_tab_walk_the_table() {
        let rows = [
            ("Action.\n", BlockKind::Action, Some(BlockKind::Character)),
            (
                "@JOHN\nHi.\n",
                BlockKind::Character,
                Some(BlockKind::Parenthetical),
            ),
            (
                "JOHN\nHello.\n",
                BlockKind::Dialogue,
                Some(BlockKind::Parenthetical),
            ),
            ("INT. HOUSE - DAY\n", BlockKind::SceneHeading, None),
            ("JOHN\n(quietly)\nHi.\n", BlockKind::Parenthetical, None),
            (">CUT TO:\n", BlockKind::Transition, None),
            ("/* hidden */\n", BlockKind::Opaque, None),
        ];
        for (source, from, expected) in rows {
            let doc = Doc::parse(source);
            let index = doc
                .kinds()
                .iter()
                .position(|kind| *kind == from)
                .unwrap_or_else(|| panic!("{source:?} has no {from:?} block"));
            let text = doc.blocks()[index].text.clone();
            assert_eq!(
                doc_tab_target(doc.handle(), doc.id(index), false),
                expected,
                "the hint for Tab from {from:?}"
            );

            match (doc.tab(doc.end_of(index), false), expected) {
                (None, None) => {}
                (Some(result), Some(kind)) => {
                    assert_eq!(result.changed[0].kind, kind, "Tab from {from:?}");
                    assert_eq!(result.changed[0].text, text, "Tab never alters the text");
                    assert!(result.changed[0].forced, "Tab pins the choice");
                }
                (got, _) => panic!("Tab from {from:?} answered {got:?}, wanted {expected:?}"),
            }
        }
    }

    #[test]
    fn shift_tab_returns_to_where_tab_came_from() {
        // Action → Character → Action.
        let doc = Doc::parse("JOHN\n");
        assert_eq!(doc.kinds(), [BlockKind::Action]);
        doc.tab(doc.end_of(0), false).expect("Tab moves");
        assert_eq!(doc.kinds(), [BlockKind::Character]);
        doc.tab(doc.end_of(0), true).expect("Shift+Tab moves back");
        assert_eq!(doc.kinds(), [BlockKind::Action]);

        // A parenthetical under a cue goes back to a cue; under a speech, to a
        // speech.
        let under_cue = Doc::parse("@JOHN\n(quietly)\n");
        under_cue.tab(under_cue.end_of(1), true).expect("moves");
        assert_eq!(under_cue.blocks()[1].kind, BlockKind::Character);

        let under_speech = Doc::parse("JOHN\nHello.\n(quietly)\n");
        assert_eq!(under_speech.blocks()[2].kind, BlockKind::Parenthetical);
        under_speech
            .tab(under_speech.end_of(2), true)
            .expect("moves");
        assert_eq!(under_speech.blocks()[2].kind, BlockKind::Dialogue);
    }

    #[test]
    fn tab_from_action_to_a_cue_makes_the_speech_under_it_dialogue() {
        // The workflow the table exists for: type a name, Tab, Enter, speak.
        let doc = Doc::new();
        doc.types(0, "JOHN");
        doc.tab(doc.end_of(0), false).expect("Tab moves");
        let created = doc.enter(doc.end_of(0)).inserted[0].block.id;
        assert_eq!(doc.kinds(), [BlockKind::Character, BlockKind::Dialogue]);

        let at = DocPosition {
            block: created,
            offset_utf16: 0,
        };
        doc_apply(
            doc.handle(),
            EditCommand::ReplaceText {
                block: created,
                start_utf16: 0,
                end_utf16: 0,
                with: "Hello.".to_owned(),
            },
            Some(DocSelection {
                anchor: at,
                focus: at,
            }),
        );

        assert_eq!(doc.kinds(), [BlockKind::Character, BlockKind::Dialogue]);
        assert_eq!(doc.text(), "@JOHN\nHello.\n");
    }

    #[test]
    fn a_tab_on_a_stale_handle_answers_none() {
        let handle = doc_new();
        let at = DocPosition {
            block: 1,
            offset_utf16: 0,
        };
        let caret = DocSelection {
            anchor: at,
            focus: at,
        };
        doc_close(handle);
        assert!(doc_tab(handle, caret, false).is_none());
        assert!(doc_tab_target(handle, 1, false).is_none());
        assert!(doc_character_suggestion(handle, 1).is_none());
        assert!(doc_find(handle, find("x")).is_empty());
    }

    // --- find and replace ------------------------------------------------

    fn find(text: &str) -> FindQuery {
        FindQuery {
            text: text.to_owned(),
            case_sensitive: false,
            whole_word: false,
            kinds: Vec::new(),
        }
    }

    #[test]
    fn find_answers_in_dart_coordinates() {
        let doc = Doc::parse("aé日🎬 café\n");
        let hits = doc_find(doc.handle(), find("café"));
        assert_eq!(hits.len(), 1);
        // 'aé日🎬 ' is 6 UTF-16 units and 12 bytes; Dart must be told 6.
        assert_eq!(hits[0].start_utf16, 6);
        assert_eq!(hits[0].end_utf16, 10);
        assert_eq!(hits[0].block, doc.id(0));
    }

    #[test]
    fn find_reports_every_hit_in_order() {
        let doc = Doc::parse("INT. HOUSE - DAY\n\nJohn enters the house.\n");
        let hits = doc_find(doc.handle(), find("house"));
        assert_eq!(hits.len(), 2);
        assert_eq!(hits[0].block, doc.id(0));
        assert_eq!(hits[1].block, doc.id(1));
    }

    #[test]
    fn find_can_be_restricted_to_element_types() {
        let doc = Doc::parse("# Act one\n\n## Act two\n\nAct three.\n");
        let sections = FindQuery {
            kinds: vec![BlockKind::Section],
            ..find("act")
        };
        assert_eq!(
            doc_find(doc.handle(), sections).len(),
            2,
            "a Section filter covers every level"
        );
    }

    #[test]
    fn replace_all_is_one_undo_step() {
        let source = "INT. HOUSE - DAY\n\nJohn enters the house.\n";
        let doc = Doc::parse(source);
        let EditOutcome::Applied { result } =
            doc_replace_all(doc.handle(), find("house"), "cabin".to_owned())
        else {
            panic!("the replacement applies");
        };
        assert_eq!(result.changed.len(), 2);
        assert_eq!(doc.blocks()[0].text, "INT. cabin - DAY");

        doc_undo(doc.handle()).expect("one step takes all of it back");
        assert_eq!(doc.text(), source);
        assert!(doc_undo(doc.handle()).is_none());
    }

    #[test]
    fn replace_all_with_nothing_to_replace_leaves_no_undo_step() {
        let doc = Doc::parse("Action.\n");
        doc_replace_all(doc.handle(), find("absent"), "x".to_owned());
        assert!(doc_undo(doc.handle()).is_none());
        assert_eq!(doc.text(), "Action.\n");
    }

    // --- suggestions -----------------------------------------------------

    #[test]
    fn an_existing_cue_is_suggested_but_never_applied() {
        let doc = Doc::parse("JOHN\nHello.\n\nJOHN\n");
        assert_eq!(
            doc_character_suggestion(doc.handle(), doc.id(2)).as_deref(),
            Some("JOHN")
        );
        assert_eq!(
            doc.kinds(),
            [BlockKind::Character, BlockKind::Dialogue, BlockKind::Action],
            "a suggestion changes nothing on its own"
        );
        assert_eq!(doc_character_suggestion(doc.handle(), doc.id(1)), None);
    }

    #[test]
    fn pasting_nothing_changes_nothing() {
        let doc = Doc::parse(SCRIPT);
        let caret = DocSelection {
            anchor: DocPosition {
                block: doc.id(1),
                offset_utf16: 4,
            },
            focus: DocPosition {
                block: doc.id(1),
                offset_utf16: 4,
            },
        };
        doc_paste(doc.handle(), caret, String::new(), false);
        assert_eq!(doc.text(), SCRIPT);
        assert!(doc_undo(doc.handle()).is_none());
    }
}
