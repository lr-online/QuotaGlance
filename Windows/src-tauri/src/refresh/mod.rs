//! Refresh scheduling. Mirrors Swift
//! `Sources/QuotaGlanceCore/Refresh/RefreshCoordinator.swift`. Two surfaces:
//!
//! - [`refresh_coordinator::RefreshCoordinator`]: orchestrates provider
//!   refresh (single / batch). Failure-isolated: one
//!   account's HTTP / spec failure does not short-circuit the others.

pub mod refresh_coordinator;
pub mod refresh_run;
