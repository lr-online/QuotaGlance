//! Provider layer for the QuotaGlance Windows engine. Mirrors
//! `Sources/QuotaGlanceCore/Providers/`. The public surface is small:
//!
//! - [`usage_provider`]: the `UsageProvider` trait + `ProviderDetection` +
//!   `ProviderDescriptor`.
//! - [`provider_error`]: the cross-platform error-token table + the
//!   `ProviderError`/`TransportError` enums.
//! - [`http_client`]: the transport seam the spec engine talks to.
//! - [`provider_spec`]: the spec data model + the `KNOWN_*` allow-lists
//!   the engine validates against. Mirrors `ProviderSpec.swift`.
//! - [`spec_driven_provider`]: the per-provider adapter that loads the
//!   spec, runs `detect`/`fetch`, and merges multi-step snapshots.
//!   Mirrors `SpecDrivenProvider.swift`.
//! - [`minimax_model_remains_strategy`]: the only named parse strategy
//!   (`parseStrategy: "miniMaxModelRemains"`). Mirrors
//!   `MiniMaxModelRemainsStrategy.swift`.

pub mod contract_provider;
pub mod http_client;
pub mod minimax_model_remains_strategy;
pub mod provider_error;
pub mod provider_spec;
pub mod spec_driven_provider;
pub mod spec_engine;
pub mod usage_provider;
