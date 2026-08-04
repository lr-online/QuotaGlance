// `UsageProvider` trait and the few cross-platform types it carries.
//
// Mirrors `Sources/QuotaGlanceCore/Providers/UsageProvider.swift`. The trait
// has exactly four members: `id`, `descriptor`, `detect`, `fetch`. Nothing
// else belongs here; per-provider behaviour lives in `SpecDrivenProvider`,
// not in this file.

use async_trait::async_trait;

use crate::domain::{ProviderID, ProviderProfile, ProviderUsageSnapshot};
use crate::providers::provider_error::ProviderError;

/// Result of running `detect`. Bundles the parsed profile with the snapshot
/// the spec engine produced while running the fetch pipeline under it.
#[derive(Debug, Clone, PartialEq)]
pub struct ProviderDetection {
    pub profile: ProviderProfile,
    pub snapshot: ProviderUsageSnapshot,
}

impl ProviderDetection {
    pub fn new(profile: ProviderProfile, snapshot: ProviderUsageSnapshot) -> Self {
        Self { profile, snapshot }
    }
}

/// Capability descriptor for a provider. Mirrors Swift `ProviderDescriptor`
/// closed-set:
///   - `supports_low_balance_threshold`: always true | per-credential-kind true
///   - `profile_description` style: unresolved L10n key + arguments
///
/// These fields are populated by `SpecDrivenProvider` from the spec's
/// `descriptor` block. The struct is the cross-platform surface used by the
/// presentation layer (account edit form, settings).
#[derive(Debug, Clone, PartialEq)]
pub struct ProviderDescriptor {
    pub supports_low_balance_threshold: bool,
}

impl ProviderDescriptor {
    pub fn always_supports_low_balance_threshold() -> Self {
        Self { supports_low_balance_threshold: true }
    }
}

#[async_trait]
pub trait UsageProvider: Send + Sync {
    fn id(&self) -> ProviderID;

    fn descriptor(&self) -> &ProviderDescriptor;

    /// Probe a candidate API key under the provider's `detect` strategy.
    /// See `Contracts/README.md` "detect". The returned `ProviderDetection`
    /// carries the snapshot the engine produced while running the fetch
    /// pipeline under the detected profile.
    async fn detect(&self, api_key: &str) -> Result<ProviderDetection, ProviderError>;

    /// Run the spec `fetch` pipeline under the requested profile. The
    /// profile must equal a `profiles.supported` entry; mismatch throws
    /// `profileMismatch` here.
    async fn fetch(
        &self,
        api_key: &str,
        profile: ProviderProfile,
    ) -> Result<ProviderUsageSnapshot, ProviderError>;
}
