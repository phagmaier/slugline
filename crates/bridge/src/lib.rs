pub mod api;
mod frb_generated;

/// The only place UTF-16 ↔ UTF-8 conversion is allowed to happen (§2.4).
pub mod offsets;
