pub mod api;
mod frb_generated;

/// One dedicated thread owns the state; everything else asks it (§2.3).
mod actor;
mod state;

/// The only place UTF-16 ↔ UTF-8 conversion is allowed to happen (§2.4).
pub mod offsets;
