//! Persistence layer. Mirrors `Sources/QuotaGlanceCore/Storage/`:
//!
//! - [`path_layout`]: canonical paths (`%LOCALAPPDATA%\QuotaGlance\` by
//!   default, optional `PORTABLE=1` redirect to the executable's parent
//!   directory) and atomic-write helper.
//! - [`credential_vault`]: per-machine DPAPI-encrypted API-key store. On
//!   non-Windows targets a debug-feature stub returns the key verbatim.
//! - [`account_store`], [`snapshot_store`]: JSON files; atomic writes
//!   mirror Swift's `temp + rename` strategy.
//! - [`preferences`]: per-machine JSON file for refresh interval, locale,
//!   notifications, launch-at-login, default widget target.

pub mod account_store;
pub mod credential_vault;
pub mod path_layout;
pub mod preferences;
pub mod snapshot_store;
