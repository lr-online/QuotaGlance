//! Aggregation engine for the QuotaGlance Windows engine.
//!
//! Mirrors `Sources/QuotaGlanceCore/Aggregation/SnapshotAggregator.swift`.
//! Filters disabled accounts, sorts by `sortOrder`, copies display metadata
//! from each account onto its snapshot, sums balances per currency, computes
//! the today cost / today requests only when all enabled accounts agree on
//! currency (and a separate Int64 overflow check produces `isPartial`), and
//! builds a 7-day `dailyUsage` window that zero-fills missing days.

mod snapshot_aggregator;

pub use snapshot_aggregator::SnapshotAggregator;
