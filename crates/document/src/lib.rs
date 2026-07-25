//! Canonical document model: blocks, edit commands, undo/redo, entity index.
//!
//! Layering rule (§2.5): may depend on `fountain` only.
//!
//! Phase 0 placeholder — the model in §3 lands in Phase 2.

/// Stable for the lifetime of a loaded document. Never reused after deletion.
#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord, Hash)]
pub struct BlockId(pub u64);

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn block_ids_compare_by_value() {
        assert_eq!(BlockId(7), BlockId(7));
        assert_ne!(BlockId(7), BlockId(8));
    }

    #[test]
    fn can_reach_the_fountain_crate() {
        assert_eq!(screenplay_fountain::FORMAT_NAME, "fountain");
    }
}
