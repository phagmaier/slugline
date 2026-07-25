//! Fountain parsing and serialisation.
//!
//! Layering rule (§2.5): this crate depends on nothing else in the workspace and
//! performs no I/O. It is a pure function from bytes to a syntax tree and back.
//!
//! Phase 0 placeholder — the real parser lands in Phase 1.

/// Name of the format this crate reads and writes.
pub const FORMAT_NAME: &str = "fountain";

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn crate_is_wired_into_the_workspace() {
        assert_eq!(FORMAT_NAME, "fountain");
    }
}
