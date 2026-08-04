//! Refresh scheduling. Mirrors Swift
//! `Sources/QuotaGlanceCore/Refresh/RefreshCoordinator.swift`. Two surfaces:
//!
//! - [`refresh_coordinator::RefreshCoordinator`]: orchestrates per-account
//!   refresh (single / batch / interval / launch). Failure-isolated: one
//!   account's HTTP / spec failure does not short-circuit the others.

pub mod refresh_coordinator;
