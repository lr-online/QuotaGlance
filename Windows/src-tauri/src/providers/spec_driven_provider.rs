// SpecDrivenProvider orchestrates spec load, detect, and fetch.
//
// Mirrors `Sources/QuotaGlanceCore/Providers/SpecDrivenProvider.swift`. The
// high-level flow:
//
//   1. `load(spec_json)` -> `SpecDrivenProvider { spec }`.
//   2. `detect(api_key)` walks `spec.detect.steps` against the spec, with
//      `${apiKey}` substituted, and returns the first `ProviderDetection`
//      whose step succeeded. On `invalidCredential` it falls through to
//      the next `profiles.supported` entry (the spec-driven region
//      fallback). On any other error it surfaces verbatim.
//   3. `fetch(api_key, profile)` runs `spec.fetch.steps` under the
//      requested profile, merging captured aliases onto the
//      ProviderUsageSnapshot field-by-field through SpecSnapshotAssembly.
//
// Failure isolation: a profile detection that fails is invisible to
// fetch. Multi-step responses merge into a single snapshot.

use std::sync::Arc;

use serde_json::Value;
use uuid::Uuid;

use crate::domain::{
    Account, AccountHealth, ProviderID, ProviderProfile, ProviderUsageSnapshot,
};
use crate::providers::http_client::{HttpClient, RawResponse};
use crate::providers::provider_error::ProviderError;
use crate::providers::provider_spec::{Spec, SpecPipeline, SpecStep};
use crate::providers::spec_engine::{SpecEngine, SpecError, SpecSnapshotAssembly};
use crate::providers::usage_provider::{ProviderDetection, ProviderDescriptor, UsageProvider};
use crate::providers::minimax_model_remains_strategy::{
    parse_input, MiniMaxModelRemainsStrategy,
};

/// Outcome of running one spec step: either `Pass` with a captured
/// alias map and the final `onStatus`-bound HTTP status, or `Fail(reason)`.
#[derive(Debug, Clone)]
pub(crate) enum StepOutcome {
    Pass(std::collections::HashMap<String, Value>),
    Fail(ProviderError),
}

/// One loaded provider with its spec. Thread-safe (spec is immutable,
/// HTTP client is `Arc`'d so seam swaps from tests are cheap).
pub struct SpecDrivenProvider {
    pub spec_engine: SpecEngine,
    pub descriptor: ProviderDescriptor,
    pub id: ProviderID,
    pub http: Arc<dyn HttpClient>,
}

impl SpecDrivenProvider {
    pub fn new(
        spec: Spec,
        descriptor: ProviderDescriptor,
        id: ProviderID,
        http: Arc<dyn HttpClient>,
    ) -> Self {
        let engine = SpecEngine::load(&serde_json::to_value(&spec).unwrap_or_default())
            .expect("spec must validate against KNOWN_* allow-lists before being passed in");
        Self {
            spec_engine: engine,
            descriptor,
            id,
            http,
        }
    }

    /// Run the detect pipeline; mirror of
    /// `SpecDrivenProvider.detect(apiKey: String)` in Swift.
    pub async fn detect_internal(
        &self,
        api_key: &str,
    ) -> Result<ProviderDetection, ProviderError> {
        for profile_entry in &self.spec_engine.spec.profiles.supported {
            let profile = ProviderProfile::new(profile_entry.region, profile_entry.credential_kind);
            match self.try_fetch_under(api_key, profile, &self.spec_engine.spec.detect).await {
                Ok(snapshot) => {
                    return Ok(ProviderDetection::new(profile, snapshot));
                }
                Err(err) => {
                    if err.is_region_fallback_trigger() {
                        continue;
                    }
                    return Err(err);
                }
            }
        }
        Err(ProviderError::RegionDetectionFailed)
    }

    pub async fn fetch_internal(
        &self,
        api_key: &str,
        profile: ProviderProfile,
    ) -> Result<ProviderUsageSnapshot, ProviderError> {
        let requested = self
            .spec_engine
            .spec
            .profiles
            .supported
            .iter()
            .find(|p| p.region == profile.region && p.credential_kind == profile.credential_kind)
            .ok_or(ProviderError::ProfileMismatch)?;
        let _ = requested; // profile candidate validated.

        self.try_fetch_under(api_key, profile, &self.spec_engine.spec.fetch).await
    }

    async fn try_fetch_under(
        &self,
        api_key: &str,
        _profile: ProviderProfile,
        pipeline: &SpecPipeline,
    ) -> Result<ProviderUsageSnapshot, ProviderError> {
        let mut captures: std::collections::HashMap<String, Value> =
            std::collections::HashMap::new();
        let mut snapshot = ProviderUsageSnapshot::default();

        for step in &pipeline.steps {
            let outcome = self.run_step(step, api_key).await?;
            captures.extend(outcome.0);

            // Apply the spec's `specFields` rules onto the cumulative snapshot.
            match SpecSnapshotAssembly::assemble(&step.spec_fields, &captures) {
                Ok(fields) => apply_fields(&mut snapshot, &fields),
                Err(err) => {
                    tracing::warn!(?err, step_id = %step.id, "spec assembly rejected step");
                    return Err(ProviderError::InvalidResponse);
                }
            }
        }
        Ok(snapshot)
    }

    async fn run_step(
        &self,
        step: &SpecStep,
        api_key: &str,
    ) -> Result<(std::collections::HashMap<String, Value>,), ProviderError> {
        let url = self.spec_engine.substitute_api_key(&step.request.url.template, api_key);
        let headers: Vec<(String, String)> = step
            .request
            .headers
            .iter()
            .map(|h| {
                (
                    h.name.clone(),
                    self.spec_engine.substitute_api_key(&h.value, api_key),
                )
            })
            .collect();
        let header_refs: Vec<(&str, &str)> = headers
            .iter()
            .map(|(k, v)| (k.as_str(), v.as_str()))
            .collect();

        let raw: RawResponse = self
            .http
            .get_json(&url, &header_refs)
            .await
            .map_err(|e| match e {
                crate::providers::provider_error::TransportError::Offline => {
                    ProviderError::HttpStatus(0)
                }
                crate::providers::provider_error::TransportError::Timeout => {
                    ProviderError::HttpStatus(0)
                }
                _ => ProviderError::InvalidResponse,
            })?;

        // onStatus first-match dispatch: a step can override specific
        // HTTP codes with a ProviderError token. If no match, the engine
        // keeps the raw response.
        if let Some(token) = step.on_status.get(&raw.status) {
            return Err(map_token_to_error(token));
        }
        if raw.status >= 400 {
            return Err(ProviderError::HttpStatus(raw.status));
        }

        self.spec_engine.run_checks(&raw.body, &step.checks)?;
        let parsed = self.spec_engine.parse_response(&raw.body, &step.parse)?;
        let captures = apply_strategies(&parsed)?;
        Ok((captures,))
    }
}

/// Apply `parseStrategy = "miniMaxModelRemains"` rules in `captures`
/// and materialise the parsed alias as a serialised snapshot. The spec
/// engine pre-parses; this function dispatches to the strategy module
/// and re-emits the resulting snapshot as JSON.
fn apply_strategies(
    captures: &std::collections::HashMap<String, Value>,
) -> Result<std::collections::HashMap<String, Value>, ProviderError> {
    let mut out = std::collections::HashMap::new();
    for (alias, value) in captures {
        if let Some(strategy) = value.get("$strategy").and_then(|v| v.as_str()) {
            if strategy == "miniMaxModelRemains" {
                let input = parse_input(value).map_err(|_| ProviderError::InvalidResponse)?;
                let cap_step = value
                    .get("$capStep")
                    .and_then(|v| v.as_str())
                    .and_then(|s| rust_decimal::Decimal::from_str_exact(s).ok())
                    .unwrap_or(rust_decimal::Decimal::from(50_000));
                let currency = value
                    .get("$currency")
                    .and_then(|v| v.as_str())
                    .unwrap_or("USD");
                let snap = MiniMaxModelRemainsStrategy::build_snapshot(
                    &input,
                    chrono::Utc::now(),
                    cap_step,
                    currency,
                );
                let json = serde_json::to_value(&snap).map_err(|_| ProviderError::InvalidResponse)?;
                out.insert(alias.clone(), json);
            } else {
                return Err(ProviderError::InvalidResponse);
            }
        } else {
            out.insert(alias.clone(), value.clone());
        }
    }
    Ok(out)
}

fn apply_fields(snapshot: &mut ProviderUsageSnapshot, fields: &std::collections::BTreeMap<String, Value>) {
    for (k, v) in fields {
        match k.as_str() {
            "balances" => {
                snapshot.balances = serde_json::from_value(v.clone()).unwrap_or_default();
            }
            "today" => {
                snapshot.today = serde_json::from_value(v.clone()).ok();
            }
            "total" => {
                snapshot.total = serde_json::from_value(v.clone()).ok();
            }
            "dailyUsage" => {
                snapshot.daily_usage = serde_json::from_value(v.clone()).unwrap_or_default();
            }
            "modelUsage" => {
                snapshot.model_usage = serde_json::from_value(v.clone()).unwrap_or_default();
            }
            "quotaWindows" => {
                snapshot.quota_windows = serde_json::from_value(v.clone()).unwrap_or_default();
            }
            "spend" => {
                snapshot.spend = serde_json::from_value(v.clone()).unwrap_or_default();
            }
            "spendingLimit" => {
                snapshot.spending_limit = serde_json::from_value(v.clone()).ok();
            }
            "providerStatus" => {
                snapshot.provider_status = v.as_str().map(|s| s.to_string());
            }
            "metricsUnavailableReason" => {
                snapshot.metrics_unavailable_reason = v.as_str().map(|s| s.to_string());
            }
            _ => {}
        }
    }
}

fn map_token_to_error(token: &str) -> ProviderError {
    match token {
        "invalidCredential" => ProviderError::InvalidCredential,
        "rateLimited" => ProviderError::RateLimited,
        "invalidResponse" => ProviderError::InvalidResponse,
        "providerInactive" => ProviderError::ProviderInactive,
        "unsupportedCredential" => ProviderError::UnsupportedCredential,
        "regionDetectionFailed" => ProviderError::RegionDetectionFailed,
        "profileMismatch" => ProviderError::ProfileMismatch,
        // httpStatus tokens are emitted by the spec at parse time rather
        // than here; the dedicated `httpStatus:<code>` form is mapped by
        // the runtime when the spec author chose to surface the actual
        // numeric code.
        "httpStatus" => ProviderError::InvalidResponse,
        _other => ProviderError::InvalidResponse,
    }
}

#[async_trait::async_trait]
impl UsageProvider for SpecDrivenProvider {
    fn id(&self) -> ProviderID {
        self.id
    }

    fn descriptor(&self) -> &ProviderDescriptor {
        &self.descriptor
    }

    async fn detect(
        &self,
        api_key: &str,
    ) -> Result<ProviderDetection, ProviderError> {
        self.detect_internal(api_key).await
    }

    async fn fetch(
        &self,
        api_key: &str,
        profile: ProviderProfile,
    ) -> Result<ProviderUsageSnapshot, ProviderError> {
        self.fetch_internal(api_key, profile).await
    }
}

/// Helper for the storage layer: build a fresh `Account` row for the
/// not-yet-persisted discovery result.
pub fn new_account_for(provider: ProviderID, display_name: &str, profile: ProviderProfile) -> Account {
    Account::new(Uuid::new_v4(), display_name.to_string(), provider, Some(profile), 0)
}

/// Mark an account's health after a refresh attempt. Consumed by the
/// refresh coordinator; mirrors `Account.assess(usage:health:lastSuccessAt:)`
/// in Swift.
pub fn assess_health(snapshot: &ProviderUsageSnapshot) -> AccountHealth {
    if snapshot.balances.is_empty()
        && snapshot.today.is_none()
        && snapshot.total.is_none()
        && snapshot.daily_usage.is_empty()
        && snapshot.model_usage.is_empty()
        && snapshot.metrics_unavailable_reason.is_some()
    {
        AccountHealth::Unavailable(crate::domain::SnapshotFailure::ProviderError)
    } else {
        AccountHealth::Healthy
    }
}

// `SpecError` is the engine-level error type; the trait lets the test
// suite reference both modules without a hard compile-time coupling.
#[allow(dead_code)]
fn spec_error_marker(_: SpecError) {}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::domain::ProviderRegion;
    use crate::providers::http_client::RawResponse;
    use async_trait::async_trait;

    /// Recording stub used by `apply_strategies` tests.
    #[derive(Debug, Default)]
    struct Recorder;

    #[async_trait]
    impl HttpClient for Recorder {
        async fn get_json(
            &self,
            _url: &str,
            _headers: &[(&str, &str)],
        ) -> Result<RawResponse, crate::providers::provider_error::TransportError> {
            Ok(RawResponse {
                status: 200,
                body: serde_json::json!({}),
            })
        }
    }

    #[test]
    fn assess_health_picks_unavailable_when_metrics_missing() {
        let snap = ProviderUsageSnapshot {
            metrics_unavailable_reason: Some("empty".into()),
            received_at: chrono::Utc::now(),
            ..Default::default()
        };
        assert!(matches!(
            assess_health(&snap),
            AccountHealth::Unavailable(_)
        ));
    }

    #[test]
    fn new_account_for_fills_uuid_and_profile() {
        let account = new_account_for(ProviderID::OpenRouter, "demo", ProviderProfile::new(ProviderRegion::Global, crate::domain::ProviderCredentialKind::Standard));
        assert_eq!(account.display_name, "demo");
        assert_eq!(account.provider, ProviderID::OpenRouter);
        assert_eq!(account.detected_profile.unwrap().region, ProviderRegion::Global);
    }
}
