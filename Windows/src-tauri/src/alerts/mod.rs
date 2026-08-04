//! Alert evaluator for the QuotaGlance Windows engine. Mirrors
//! `Sources/QuotaGlanceCore/Alerts/AlertEvaluator.swift`. Threshold compare
//! uses exact decimal strings, the episode state lives on the `Account`
//! itself (mutated in place to keep I/O out of the engine), and stale /
//! unavailable fresh snapshots never advance the episode either direction.

mod alert_evaluator;

pub use alert_evaluator::{AlertAction, AlertBatchEvaluation, AlertEvaluator, PendingLowBalanceNotification};
