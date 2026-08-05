// Domain layer for the QuotaGlance Windows engine.
//
// This file is a Rust mirror of Sources/QuotaGlanceCore/Domain/. It must stay
// structurally identical to the Swift and ArkTS counterparts so the contract
// fixture suite (Contracts/Providers/<id>/<case>-{response,expected,requests}.json,
// Contracts/Aggregation/, Contracts/Alerts/) drives all four engines without
// shape adapters.
//
// Swift sendable shadow types are encoded with serde here. The `Decimal`
// fields use `rust_decimal::Decimal` for arithmetic; money amounts are kept
// as String so they match the canonical ArkTS form ("6655.9", not 6655.90)
// that contract fixtures pin verbatim.

use std::collections::HashMap;
use std::fmt;

use chrono::{DateTime, Utc};
use rust_decimal::Decimal;
use serde::{Deserialize, Serialize};
use uuid::Uuid;

// ---------------------------------------------------------------------------
// Money
// ---------------------------------------------------------------------------

/// `Money {amount, currency}`. `amount` is the canonical decimal string the
/// spec engine produces (JSON-number source: shortest round-trip; JSON-string
/// source: trimmed verbatim; `subtract`: canonical rendering of the exact
/// result). Currency is upper-cased by the engine before reaching here.
#[derive(Debug, Clone, Default, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub struct Money {
    pub amount: String,
    pub currency: String,
}

impl Money {
    pub fn new(amount: impl Into<String>, currency: impl Into<String>) -> Self {
        Self {
            amount: amount.into(),
            currency: currency.into(),
        }
    }

    /// Numeric view of the amount. Pure arithmetic helpers; never round-trips
    /// through this representation in fixture output.
    pub fn amount_decimal(&self) -> Option<Decimal> {
        Decimal::from_str_exact(&self.amount).ok()
    }

    pub fn is_zero(&self) -> bool {
        self.amount_decimal().map(|d| d.is_zero()).unwrap_or(false)
    }
}

// ---------------------------------------------------------------------------
// ProviderID
// ---------------------------------------------------------------------------

/// Mirror of Swift `ProviderID` raw values. Order MUST stay aligned with
/// `Sources/QuotaGlanceCore/Domain/Provider.swift`'s `allCases` array. New
/// cases are append-only across all four platforms; renaming or deleting
/// would break persisted account records.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub enum ProviderID {
    #[serde(rename = "apiInfo")]
    ApiInfo,
    #[serde(rename = "deepSeek")]
    DeepSeek,
    #[serde(rename = "kimi")]
    Kimi,
    #[serde(rename = "openRouter")]
    OpenRouter,
    #[serde(rename = "miniMax")]
    MiniMax,
    #[serde(rename = "bioMapCoding")]
    BioMapCoding,
}

impl ProviderID {
    /// Append-only, ordered list. Matches Swift's explicit `allCases` array.
    pub const ALL_CASES: &'static [ProviderID] = &[
        Self::ApiInfo,
        Self::DeepSeek,
        Self::Kimi,
        Self::OpenRouter,
        Self::MiniMax,
        Self::BioMapCoding,
    ];

    pub fn raw_value(self) -> &'static str {
        match self {
            Self::ApiInfo => "apiInfo",
            Self::DeepSeek => "deepSeek",
            Self::Kimi => "kimi",
            Self::OpenRouter => "openRouter",
            Self::MiniMax => "miniMax",
            Self::BioMapCoding => "bioMapCoding",
        }
    }

    pub fn from_raw(s: &str) -> Option<Self> {
        match s {
            "apiInfo" => Some(Self::ApiInfo),
            "deepSeek" => Some(Self::DeepSeek),
            "kimi" => Some(Self::Kimi),
            "openRouter" => Some(Self::OpenRouter),
            "miniMax" => Some(Self::MiniMax),
            "bioMapCoding" => Some(Self::BioMapCoding),
            _ => None,
        }
    }
}

impl fmt::Display for ProviderID {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str(self.raw_value())
    }
}

// ---------------------------------------------------------------------------
// Region / credential kind / profile
// ---------------------------------------------------------------------------

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub enum ProviderRegion {
    #[serde(rename = "global")]
    Global,
    #[serde(rename = "china")]
    China,
    #[serde(rename = "international")]
    International,
}

impl ProviderRegion {
    pub fn raw_value(self) -> &'static str {
        match self {
            Self::Global => "global",
            Self::China => "china",
            Self::International => "international",
        }
    }

    pub fn from_raw(s: &str) -> Option<Self> {
        match s {
            "global" => Some(Self::Global),
            "china" => Some(Self::China),
            "international" => Some(Self::International),
            _ => None,
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub enum ProviderCredentialKind {
    #[serde(rename = "standard")]
    Standard,
    #[serde(rename = "management")]
    Management,
    #[serde(rename = "tokenPlan")]
    TokenPlan,
}

impl ProviderCredentialKind {
    pub fn raw_value(self) -> &'static str {
        match self {
            Self::Standard => "standard",
            Self::Management => "management",
            Self::TokenPlan => "tokenPlan",
        }
    }

    pub fn from_raw(s: &str) -> Option<Self> {
        match s {
            "standard" => Some(Self::Standard),
            "management" => Some(Self::Management),
            "tokenPlan" => Some(Self::TokenPlan),
            _ => None,
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub struct ProviderProfile {
    pub region: ProviderRegion,
    pub credential_kind: ProviderCredentialKind,
}

impl ProviderProfile {
    pub fn new(region: ProviderRegion, credential_kind: ProviderCredentialKind) -> Self {
        Self { region, credential_kind }
    }

    /// Matches Swift `ProviderProfile.apiInfo` literal.
    pub const API_INFO: Self = Self {
        region: ProviderRegion::Global,
        credential_kind: ProviderCredentialKind::Standard,
    };
}

// ---------------------------------------------------------------------------
// Usage counters / spending / windows / daily / model usage
// ---------------------------------------------------------------------------

#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct UsageCounters {
    #[serde(skip_serializing_if = "Option::is_none", default)]
    pub actual_cost: Option<Money>,
    #[serde(skip_serializing_if = "Option::is_none", default)]
    pub requests: Option<i64>,
    #[serde(skip_serializing_if = "Option::is_none", default)]
    pub input_tokens: Option<i64>,
    #[serde(skip_serializing_if = "Option::is_none", default)]
    pub output_tokens: Option<i64>,
    #[serde(skip_serializing_if = "Option::is_none", default)]
    pub cache_read_tokens: Option<i64>,
    #[serde(skip_serializing_if = "Option::is_none", default)]
    pub cache_creation_tokens: Option<i64>,
    #[serde(skip_serializing_if = "Option::is_none", default)]
    pub total_tokens: Option<i64>,
}

#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct DailyUsage {
    pub date: String,
    pub actual_cost: Money,
    #[serde(skip_serializing_if = "Option::is_none", default)]
    pub requests: Option<i64>,
    #[serde(skip_serializing_if = "Option::is_none", default)]
    pub total_tokens: Option<i64>,
}

#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct ModelUsage {
    pub model: String,
    #[serde(skip_serializing_if = "Option::is_none", default)]
    pub actual_cost: Option<Money>,
    #[serde(skip_serializing_if = "Option::is_none", default)]
    pub requests: Option<i64>,
    #[serde(skip_serializing_if = "Option::is_none", default)]
    pub total_tokens: Option<i64>,
}

#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct MonetaryValue {
    pub label: String,
    pub value: Money,
}

#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct MonetaryBalance {
    pub label: String,
    pub available: Money,
    #[serde(default)]
    pub breakdown: Vec<MonetaryValue>,
}

#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct SpendingLimit {
    pub label: String,
    #[serde(skip_serializing_if = "Option::is_none", default)]
    pub used: Option<Money>,
    #[serde(skip_serializing_if = "Option::is_none", default)]
    pub limit: Option<Money>,
    #[serde(skip_serializing_if = "Option::is_none", default)]
    pub remaining: Option<Money>,
    #[serde(skip_serializing_if = "Option::is_none", default)]
    pub reset_description: Option<String>,
}

#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct SpendSummary {
    #[serde(skip_serializing_if = "Option::is_none", default)]
    pub today: Option<Money>,
    #[serde(skip_serializing_if = "Option::is_none", default)]
    pub week: Option<Money>,
    #[serde(skip_serializing_if = "Option::is_none", default)]
    pub month: Option<Money>,
    #[serde(skip_serializing_if = "Option::is_none", default)]
    pub total: Option<Money>,
}

impl SpendSummary {
    pub fn is_empty(&self) -> bool {
        self.today.is_none() && self.week.is_none() && self.month.is_none() && self.total.is_none()
    }
}

/// QuotaWindow. Numeric fields are kept as `Decimal?` to match Swift's
/// `Decimal?` typing. They are serialized as JSON numbers by default;
/// fixture output for `quotaWindows` uses dedicated builders under
/// `named parse strategy: miniMaxModelRemains` (see SpecDrivenProvider.ets
/// notes; the canonical Windows renderer is in
/// providers/minimax_model_remains_strategy.rs).
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct QuotaWindow {
    pub label: String,
    #[serde(skip_serializing_if = "Option::is_none", default)]
    pub used: Option<Decimal>,
    #[serde(skip_serializing_if = "Option::is_none", default)]
    pub limit: Option<Decimal>,
    #[serde(skip_serializing_if = "Option::is_none", default)]
    pub remaining: Option<Decimal>,
    pub unit: String,
    #[serde(skip_serializing_if = "Option::is_none", default)]
    pub resets_at: Option<DateTime<Utc>>,
}

// ---------------------------------------------------------------------------
// Snapshot / failure / health / account / aggregate / envelope
// ---------------------------------------------------------------------------

#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct ProviderUsageSnapshot {
    #[serde(default)]
    pub balances: Vec<MonetaryBalance>,
    #[serde(skip_serializing_if = "Option::is_none", default)]
    pub spending_limit: Option<SpendingLimit>,
    #[serde(default)]
    pub spend: SpendSummary,
    #[serde(default)]
    pub quota_windows: Vec<QuotaWindow>,
    #[serde(skip_serializing_if = "Option::is_none", default)]
    pub today: Option<UsageCounters>,
    #[serde(skip_serializing_if = "Option::is_none", default)]
    pub total: Option<UsageCounters>,
    #[serde(default)]
    pub daily_usage: Vec<DailyUsage>,
    #[serde(default)]
    pub model_usage: Vec<ModelUsage>,
    #[serde(skip_serializing_if = "Option::is_none", default)]
    pub provider_status: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none", default)]
    pub metrics_unavailable_reason: Option<String>,
    pub received_at: DateTime<Utc>,
}

impl ProviderUsageSnapshot {
    /// Convenience builder mirroring Swift's
    /// `init(remaining:quotaLimit:quotaUsed:today:total:dailyUsage:modelUsage:providerStatus:metricsUnavailableReason:receivedAt:)`.
    #[allow(clippy::too_many_arguments)]
    pub fn from_primary_balance(
        remaining: Money,
        quota_limit: Option<Money>,
        quota_used: Option<Money>,
        today: Option<UsageCounters>,
        total: Option<UsageCounters>,
        daily_usage: Vec<DailyUsage>,
        model_usage: Vec<ModelUsage>,
        provider_status: Option<String>,
        metrics_unavailable_reason: Option<String>,
        received_at: DateTime<Utc>,
    ) -> Self {
        let spending_limit = if quota_limit.is_some() || quota_used.is_some() {
            Some(SpendingLimit {
                label: "Quota".to_string(),
                used: quota_used,
                limit: quota_limit,
                remaining: None,
                reset_description: None,
            })
        } else {
            None
        };
        let spend = SpendSummary {
            today: today.as_ref().and_then(|t| t.actual_cost.clone()),
            week: None,
            month: None,
            total: total.as_ref().and_then(|t| t.actual_cost.clone()),
        };
        let balances = vec![MonetaryBalance {
            label: "Balance".to_string(),
            available: remaining,
            breakdown: Vec::new(),
        }];
        Self {
            balances,
            spending_limit,
            spend,
            quota_windows: Vec::new(),
            today,
            total,
            daily_usage,
            model_usage,
            provider_status,
            metrics_unavailable_reason,
            received_at,
        }
    }

    pub fn primary_balance(&self) -> Option<&MonetaryBalance> {
        self.balances.first()
    }

    pub fn remaining(&self) -> Option<&Money> {
        self.primary_balance().map(|b| &b.available)
    }

    pub fn quota_limit(&self) -> Option<&Money> {
        self.spending_limit.as_ref().and_then(|sl| sl.limit.as_ref())
    }

    pub fn quota_used(&self) -> Option<&Money> {
        self.spending_limit.as_ref().and_then(|sl| sl.used.as_ref())
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum SnapshotFailure {
    MissingCredential,
    KeychainAccessRequired,
    InvalidCredential,
    RateLimited,
    Offline,
    Timeout,
    InvalidResponse,
    ProviderError,
}

impl SnapshotFailure {
    pub fn raw_value(self) -> &'static str {
        match self {
            Self::MissingCredential => "missingCredential",
            Self::KeychainAccessRequired => "keychainAccessRequired",
            Self::InvalidCredential => "invalidCredential",
            Self::RateLimited => "rateLimited",
            Self::Offline => "offline",
            Self::Timeout => "timeout",
            Self::InvalidResponse => "invalidResponse",
            Self::ProviderError => "providerError",
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(tag = "kind", content = "failure", rename_all = "camelCase")]
pub enum AccountHealth {
    Healthy,
    BelowThreshold,
    Stale(SnapshotFailure),
    Unavailable(SnapshotFailure),
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct AccountSnapshot {
    pub account_id: Uuid,
    pub display_name: String,
    pub provider: ProviderID,
    #[serde(skip_serializing_if = "Option::is_none", default)]
    pub detected_profile: Option<ProviderProfile>,
    #[serde(skip_serializing_if = "Option::is_none", default)]
    pub low_balance_threshold: Option<Decimal>,
    #[serde(skip_serializing_if = "Option::is_none", default)]
    pub usage: Option<ProviderUsageSnapshot>,
    pub health: AccountHealth,
    #[serde(skip_serializing_if = "Option::is_none", default)]
    pub last_success_at: Option<DateTime<Utc>>,
}

impl AccountSnapshot {
    #[allow(clippy::too_many_arguments)]
    pub fn new(
        account_id: Uuid,
        display_name: String,
        provider: ProviderID,
        detected_profile: Option<ProviderProfile>,
        low_balance_threshold: Option<Decimal>,
        usage: Option<ProviderUsageSnapshot>,
        health: AccountHealth,
        last_success_at: Option<DateTime<Utc>>,
    ) -> Self {
        let detected_profile =
            detected_profile.or_else(|| matches!(provider, ProviderID::ApiInfo).then_some(ProviderProfile::API_INFO));
        Self {
            account_id,
            display_name,
            provider,
            detected_profile,
            low_balance_threshold,
            usage,
            health,
            last_success_at,
        }
    }

    pub fn remaining(&self) -> Option<&Money> {
        self.usage.as_ref().and_then(|u| u.remaining())
    }
}

/// `Account` is the persisted record (data tree, no derived snapshot data).
/// Distinct from `AccountSnapshot`, which carries the last fetched snapshot.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct Account {
    pub id: Uuid,
    pub display_name: String,
    pub provider: ProviderID,
    #[serde(skip_serializing_if = "Option::is_none", default)]
    pub detected_profile: Option<ProviderProfile>,
    #[serde(default)]
    pub is_enabled: bool,
    #[serde(default)]
    pub sort_order: i32,
    #[serde(skip_serializing_if = "Option::is_none", default)]
    pub low_balance_threshold: Option<Decimal>,
    #[serde(default)]
    pub alert_episode_active: bool,
}

impl Account {
    pub fn new(
        id: Uuid,
        display_name: String,
        provider: ProviderID,
        detected_profile: Option<ProviderProfile>,
        sort_order: i32,
    ) -> Self {
        let detected_profile = detected_profile
            .or_else(|| matches!(provider, ProviderID::ApiInfo).then_some(ProviderProfile::API_INFO));
        Self {
            id,
            display_name,
            provider,
            detected_profile,
            is_enabled: true,
            sort_order,
            low_balance_threshold: None,
            alert_episode_active: false,
        }
    }
}

#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct AggregateSnapshot {
    #[serde(default)]
    pub balances: Vec<Money>,
    #[serde(skip_serializing_if = "Option::is_none", default)]
    pub today_actual_cost: Option<Money>,
    #[serde(skip_serializing_if = "Option::is_none", default)]
    pub today_requests: Option<i64>,
    #[serde(default)]
    pub daily_usage: Vec<DailyUsage>,
    #[serde(default)]
    pub accounts: Vec<AccountSnapshot>,
    #[serde(default)]
    pub is_partial: bool,
}

impl AggregateSnapshot {
    /// Mirror of Swift's dual-init aggregator: if caller passes `balances`,
    /// that wins; otherwise `remaining` is wrapped into a single-currency
    /// list.
    pub fn new(
        remaining: Option<Money>,
        balances: Option<Vec<Money>>,
        today_actual_cost: Option<Money>,
        today_requests: Option<i64>,
        daily_usage: Vec<DailyUsage>,
        accounts: Vec<AccountSnapshot>,
        is_partial: bool,
    ) -> Self {
        let balances = balances
            .or_else(|| remaining.map(|m| vec![m]))
            .unwrap_or_default();
        Self {
            balances,
            today_actual_cost,
            today_requests,
            daily_usage,
            accounts,
            is_partial,
        }
    }

    pub fn remaining(&self) -> Option<&Money> {
        if self.balances.len() == 1 {
            self.balances.first()
        } else {
            None
        }
    }
}

/// Wire-format envelope shared with the desktop widget process.
///
/// `schemaVersion` is bumped whenever the shape changes; this is the same
/// `currentSchemaVersion = 2` Swift uses today. Older widgets can detect
/// mismatched layouts via this field.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct WidgetSnapshotEnvelope {
    pub schema_version: i32,
    pub captured_at: DateTime<Utc>,
    pub aggregate: AggregateSnapshot,
    pub accounts: Vec<AccountSnapshot>,
}

impl WidgetSnapshotEnvelope {
    pub const CURRENT_SCHEMA_VERSION: i32 = 2;

    pub fn new(captured_at: DateTime<Utc>, aggregate: AggregateSnapshot, accounts: Vec<AccountSnapshot>) -> Self {
        Self {
            schema_version: Self::CURRENT_SCHEMA_VERSION,
            captured_at,
            aggregate,
            accounts,
        }
    }

    pub fn empty(captured_at: DateTime<Utc>) -> Self {
        Self::new(captured_at, AggregateSnapshot::default(), Vec::new())
    }
}

/// Date formatter: matches Swift's `providerDateFormatter`: POSIX locale,
/// `yyyy-MM-dd`, the aggregator's calendar time-zone. Used by the daily
/// usage window in `SnapshotAggregator`.
pub fn provider_date_format(now: DateTime<Utc>) -> String {
    now.format("%Y-%m-%d").to_string()
}

/// In-memory placeholder that the storage layer fills before this file is
/// complete: list of provider IDs known at load time. Required by the
/// spec engine's `KnownProviderId` allow-list (Swift `knownErrorTokens`,
/// `knownSnapshotFields` equivalents land in `providers/provider_spec.rs`).
pub type ProviderIdSet = HashMap<ProviderID, ()>;

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn provider_id_append_only_order() {
        let order: Vec<&'static str> = ProviderID::ALL_CASES.iter().map(|id| id.raw_value()).collect();
        assert_eq!(
            order,
            vec!["apiInfo", "deepSeek", "kimi", "openRouter", "miniMax", "bioMapCoding"],
        );
    }

    #[test]
    fn money_round_trips_decimal() {
        let m = Money::new("6655.9", "USD");
        assert_eq!(m.amount_decimal().unwrap(), Decimal::new(66559, 1));
    }

    #[test]
    fn snapshot_from_primary_balance_builds_quota_limit() {
        let now = Utc::now();
        let snap = ProviderUsageSnapshot::from_primary_balance(
            Money::new("100", "USD"),
            Some(Money::new("200", "USD")),
            Some(Money::new("100", "USD")),
            None,
            None,
            Vec::new(),
            Vec::new(),
            None,
            None,
            now,
        );
        assert_eq!(snap.balances.len(), 1);
        let sl = snap.spending_limit.as_ref().expect("limit set");
        assert_eq!(sl.label, "Quota");
        assert_eq!(sl.limit.as_ref().unwrap().amount, "200");
        assert_eq!(snap.remaining().unwrap().amount, "100");
    }
}
