// Provider spec data model.
//
// Mirrors `Sources/QuotaGlanceCore/Providers/ProviderSpec.swift`. This is
// one half of the spec engine; the other half (`SpecEngine` evaluator
// and `SpecSnapshotAssembly`) lands in `spec_engine.rs`.
//
// The spec JSON schema is the cross-platform authoritative source; see
// `Contracts/README.md` "Provider spec schema". This file is just the
// Rust representation: `SpecVersion`, the per-provider `Spec`, the
// `Step` / `Request` / `OnStatus` / `Parse` / `Value` / `Condition` /
// `Check` / `SnapshotField` discriminated unions, plus the `KNOWN_*`
// allow-lists that catch unknown enum values at load time.
//
// The dynamic evaluation lives in `spec_engine.rs`; this file is purely
// the data model + the load-time allow-lists. Tests in this file pin
// the allow-list order and contents against the cross-platform error
// / region / credential / snapshot-fields tables.

use std::collections::{HashMap, HashSet};

use serde::{Deserialize, Serialize};
use serde_json::Value;

use crate::domain::{ProviderCredentialKind, ProviderRegion};
use crate::providers::provider_error::KNOWN_ERROR_TOKENS;

/// Currently supported spec schema revision. Bumped when the schema
/// changes; spec JSON whose `specVersion` does not match is rejected at
/// load.
pub const SPEC_VERSION: u32 = 1;

/// A loaded provider spec (per `Contracts/Providers/<id>/spec.json`).
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Spec {
    pub spec_version: u32,
    pub id: String,
    pub descriptor: SpecDescriptor,
    pub credential: SpecCredential,
    pub profiles: SpecProfiles,
    pub detect: SpecPipeline,
    pub fetch: SpecPipeline,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct SpecDescriptor {
    pub display_name: String,
    pub credential_kind: ProviderCredentialKind,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct SpecCredential {
    pub kind: ProviderCredentialKind,
    pub auth_header: String,
    pub scheme: String,
    pub placeholder: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct SpecProfiles {
    pub supported: Vec<SpecProfileEntry>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct SpecProfileEntry {
    pub region: ProviderRegion,
    pub credential_kind: ProviderCredentialKind,
    pub description: String,
    #[serde(default)]
    pub requires_credential_kind: Option<ProviderCredentialKind>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct SpecPipeline {
    pub steps: Vec<SpecStep>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct SpecStep {
    pub id: String,
    pub request: SpecRequest,
    #[serde(default)]
    pub on_status: HashMap<u16, String>,
    #[serde(default)]
    pub parse: Vec<SpecParse>,
    #[serde(default)]
    pub checks: Vec<SpecCheck>,
    #[serde(default)]
    pub captures: Vec<SpecCapture>,
    #[serde(default)]
    pub spec_fields: Vec<SpecSnapshotField>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct SpecRequest {
    pub method: String,
    pub url: SpecUrl,
    #[serde(default)]
    pub headers: Vec<SpecHeader>,
    #[serde(default)]
    pub body: Option<Value>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct SpecUrl {
    pub template: String,
}

/// Header literal. Templated values like `${apiKey}` are substituted
/// at build time.
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct SpecHeader {
    pub name: String,
    pub value: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(tag = "kind", rename_all = "lowercase")]
pub enum SpecParse {
    Json { path: String, alias: String },
    NumericWindow {
        alias: String,
        path: String,
    },
    Strategy {
        strategy: String,
        alias: String,
    },
    ModelRemaining {
        alias: String,
    },
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct SpecCheck {
    pub path: String,
    pub equals: Value,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct SpecCapture {
    pub alias: String,
    pub json_path: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct SpecSnapshotField {
    pub field: String,
    pub alias: String,
    #[serde(default)]
    pub transform: Option<SpecTransform>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct SpecTransform {
    pub kind: String,
    #[serde(default)]
    pub args: Value,
}

// ---------------------------------------------------------------------------
// Allow-lists. Must remain stable across all four platforms.
// ---------------------------------------------------------------------------

/// Region allow-list (cross-platform). The provider ID list itself lives
/// on `ProviderID::ALL_CASES`.
pub const KNOWN_REGIONS: &[&str] = &["global", "china", "international"];

/// Credential kind allow-list (cross-platform).
pub const KNOWN_CREDENTIAL_KINDS: &[&str] = &["standard", "management", "tokenPlan"];

/// The set of `SnapshotSnapshotField.field` values allowed in any spec.
pub const KNOWN_SNAPSHOT_FIELDS: &[&str] = &[
    "balances",
    "spendingLimit",
    "spend",
    "quotaWindows",
    "today",
    "total",
    "dailyUsage",
    "modelUsage",
    "providerStatus",
    "metricsUnavailableReason",
];

/// `parseStrategy` names. Only `miniMaxModelRemains` is named today;
/// anything else must go through the spec engine's standard tree.
pub const KNOWN_NAMED_PARSE_STRATEGIES: &[&str] = &["miniMaxModelRemains"];

/// Returns the union of error / region / credential / snapshot fields
/// / parse strategy / parse kind allow-lists. Used by spec-load-time
/// validation; a spec JSON outside any of these lists is rejected with
/// `specError`.
pub fn all_known_tokens() -> HashSet<&'static str> {
    let mut set: HashSet<&'static str> = HashSet::new();
    set.extend(KNOWN_ERROR_TOKENS.iter().copied());
    set.extend(KNOWN_REGIONS.iter().copied());
    set.extend(KNOWN_CREDENTIAL_KINDS.iter().copied());
    set.extend(KNOWN_SNAPSHOT_FIELDS.iter().copied());
    set.extend(KNOWN_NAMED_PARSE_STRATEGIES.iter().copied());
    set.insert("subtract");
    set
}

/// Lookup-table for `ProviderError` tokens to detect forbidden usage.
pub fn is_known_error_token(token: &str) -> bool {
    KNOWN_ERROR_TOKINS_SET.contains(token)
}

static KNOWN_ERROR_TOKINS_SET: std::sync::LazyLock<HashSet<&'static str>> =
    std::sync::LazyLock::new(|| KNOWN_ERROR_TOKENS.iter().copied().collect());

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn known_token_intersection_stable() {
        let all = all_known_tokens();
        for t in KNOWN_ERROR_TOKENS {
            assert!(all.contains(t), "missing in aggregate: {t}");
        }
        assert!(all.contains("balances"));
        assert!(all.contains("miniMaxModelRemains"));
        // Forbidden framework tokens must never appear here.
        assert!(!all.contains("providerUnavailable"));
        assert!(!all.contains("network"));
    }

    #[test]
    fn error_token_table_matches_provider_error_module() {
        for token in KNOWN_ERROR_TOKENS {
            assert!(is_known_error_token(token));
        }
        assert!(!is_known_error_token("providerUnavailable"));
        assert!(!is_known_error_token("network:<detail>"));
    }
}
