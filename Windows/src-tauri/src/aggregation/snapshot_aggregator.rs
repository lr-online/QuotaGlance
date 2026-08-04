// SnapshotAggregator, mirrors Sources/QuotaGlanceCore/Aggregation/SnapshotAggregator.swift.
//
// Public methods:
//   - `aggregate(accounts, snapshots, now) -> AggregateSnapshot`
//   - `sum_money_by_currency(values)`        // private helper
//   - `sum_money(values)`                   // private helper, returns Money? / null
//                                             if currencies differ.
//   - `sum_integers(values) -> Option<i64>` // private helper; returns None on
//                                             Int64 overflow.
//   - `make_daily_usage(snapshots, fallback_currency, now)` // 7-day window
//
// All Money arithmetic here operates on rust_decimal::Decimal but returns
// canonical decimal strings (Rust `rust_decimal` `to_string()` produces the
// shortest round-trip form, matching ArkTS rule "JSON number source:
// shortest round-trip rendering"). Strings that came in verbatim from a
// JSON-string source are preserved as-is.

use std::collections::BTreeMap;

use chrono::{DateTime, Duration, NaiveDate, Utc};
use rust_decimal::Decimal;

use crate::domain::{
    Account, AccountHealth, AccountSnapshot, AggregateSnapshot, DailyUsage, Money,
};

/// Cross-platform aggregator. Swift holds a `Calendar` field; the four
/// engines all consume a `now: DateTime<Utc>` injected by the caller so
/// daily-window dates are deterministic. The Rust port is stateless; if
/// per-calendar fine-tuning lands later it can live on this struct.
#[derive(Debug, Clone, Default)]
pub struct SnapshotAggregator;

impl SnapshotAggregator {
    /// Stateless mirror of Swift's `init(calendar:)`. Kept for API parity
    /// with `SnapshotAggregator();` callers in Swift.
    pub fn new() -> Self {
        Self
    }

    /// Top-level mirror of the Swift entry point.
    pub fn aggregate(
        accounts: &[Account],
        snapshots: &[AccountSnapshot],
        now: DateTime<Utc>,
    ) -> AggregateSnapshot {
        // 1. Filter to enabled accounts, sort by sortOrder then id (UUID
        //    string for stability).
        let mut enabled: Vec<&Account> = accounts.iter().filter(|a| a.is_enabled).collect();
        enabled.sort_by(|a, b| {
            a.sort_order
                .cmp(&b.sort_order)
                .then_with(|| a.id.to_string().cmp(&b.id.to_string()))
        });

        // 2. Index snapshots by account id (first wins on duplicate).
        let mut snapshots_by_id: std::collections::HashMap<uuid::Uuid, AccountSnapshot> =
            std::collections::HashMap::new();
        for snapshot in snapshots {
            snapshots_by_id
                .entry(snapshot.account_id)
                .or_insert_with(|| snapshot.clone());
        }

        // 3. Project snapshots onto the account order, copying display
        //    metadata from the account row (displayName, provider,
        //    detectedProfile, lowBalanceThreshold).
        let ordered_snapshots: Vec<AccountSnapshot> = enabled
            .iter()
            .filter_map(|account| {
                let mut snap = snapshots_by_id.get(&account.id)?.clone();
                snap.display_name = account.display_name.clone();
                snap.provider = account.provider;
                snap.detected_profile = account.detected_profile;
                snap.low_balance_threshold = account.low_balance_threshold;
                Some(snap)
            })
            .collect();

        // 4. Sum balances by currency (sort by currency code ascending).
        let balance_values: Vec<Money> = ordered_snapshots
            .iter()
            .flat_map(|s| s.usage.as_ref())
            .flat_map(|u| u.balances.iter())
            .map(|b| b.available.clone())
            .collect();
        let balances = Self::sum_money_by_currency(&balance_values);

        // 5. Today cost: only when EVERY enabled account has it; same-currency
        //    guard.
        let today_cost_values: Vec<Money> = ordered_snapshots
            .iter()
            .filter_map(|s| s.usage.as_ref())
            .filter_map(|u| u.spend.today.clone().or_else(|| u.today.as_ref()?.actual_cost.clone()))
            .collect();
        let today_cost = if today_cost_values.len() == ordered_snapshots.len()
            && !ordered_snapshots.is_empty()
        {
            Self::sum_money(&today_cost_values)
        } else {
            None
        };

        // 6. Today requests: only when all enabled accounts have it; Int64
        //    overflow -> None + isPartial.
        let today_request_values: Vec<i64> = ordered_snapshots
            .iter()
            .filter_map(|s| s.usage.as_ref())
            .filter_map(|u| u.today.as_ref())
            .filter_map(|c| c.requests)
            .collect();
        let has_all_today_requests = today_request_values.len() == ordered_snapshots.len();
        let today_requests = if has_all_today_requests && !ordered_snapshots.is_empty() {
            Self::sum_integers(&today_request_values)
        } else {
            None
        };
        let today_requests_overflowed = has_all_today_requests
            && !today_request_values.is_empty()
            && today_requests.is_none();

        // 7. 7-day window.
        let daily_usage = Self::make_daily_usage(
            &ordered_snapshots,
            if balances.len() == 1 {
                Some(balances[0].currency.clone())
            } else {
                None
            },
            now,
        );

        // 8. Partial flags.
        let is_partial = ordered_snapshots.len() != enabled.len()
            || today_requests_overflowed
            || ordered_snapshots.iter().any(|s| {
                matches!(
                    s.health,
                    AccountHealth::Stale(_) | AccountHealth::Unavailable(_)
                )
            });

        AggregateSnapshot {
            balances,
            today_actual_cost: today_cost,
            today_requests,
            daily_usage,
            accounts: ordered_snapshots,
            is_partial,
        }
    }

    /// Group by currency (sorted ascending), then sum per group.
    pub(crate) fn sum_money_by_currency(values: &[Money]) -> Vec<Money> {
        let mut groups: BTreeMap<String, Vec<Money>> = BTreeMap::new();
        for v in values {
            groups.entry(v.currency.clone()).or_default().push(v.clone());
        }
        groups
            .into_iter()
            .filter_map(|(_, group)| Self::sum_money(&group))
            .collect()
    }

    /// Sum same-currency money; returns `None` if currencies differ or list
    /// is empty.
    pub(crate) fn sum_money(values: &[Money]) -> Option<Money> {
        let first = values.first()?;
        if !values.iter().all(|v| v.currency == first.currency) {
            return None;
        }
        let total: Decimal = values
            .iter()
            .filter_map(|m| m.amount_decimal())
            .sum();
        // Canonical short form. rust_decimal::Decimal::to_string matches
        // ArkTS rule "JSON number source: shortest round-trip rendering".
        Some(Money::new(total.to_string(), first.currency.clone()))
    }

    /// Int64 sum with overflow detection (mirrors Swift
    /// `Int64.addingReportingOverflow`).
    pub(crate) fn sum_integers(values: &[i64]) -> Option<i64> {
        if values.is_empty() {
            return None;
        }
        let mut total: i64 = 0;
        for &v in values {
            match total.checked_add(v) {
                Some(sum) => total = sum,
                None => return None,
            }
        }
        Some(total)
    }

    /// 7-day window: parse `entry.date` (yyyy-MM-dd, UTC), zero-fill any
    /// missing days in the range
    /// `[max(parsed_max_date, localDay(now)) - 6, that day]`.
    pub(crate) fn make_daily_usage(
        snapshots: &[AccountSnapshot],
        fallback_currency: Option<String>,
        now: DateTime<Utc>,
    ) -> Vec<DailyUsage> {
        let entries: Vec<DailyUsage> = snapshots
            .iter()
            .filter_map(|s| s.usage.as_ref())
            .flat_map(|u| u.daily_usage.iter().cloned())
            .collect();
        if entries.is_empty() {
            return Vec::new();
        }
        let currency = match entries.first().map(|e| e.actual_cost.currency.clone()) {
            Some(c) => c,
            None => match fallback_currency {
                Some(c) => c,
                None => return Vec::new(),
            },
        };
        if !entries.iter().all(|e| e.actual_cost.currency == currency) {
            return Vec::new();
        }

        let mut parsed: Vec<(NaiveDate, DailyUsage)> = Vec::new();
        for entry in entries {
            let Ok(date) = NaiveDate::parse_from_str(&entry.date, "%Y-%m-%d") else {
                continue;
            };
            parsed.push((date, entry));
        }
        if parsed.is_empty() {
            return Vec::new();
        }
        let max_parsed = parsed.iter().map(|(d, _)| *d).max().unwrap();
        let local_today = now.date_naive();
        let end_day = if max_parsed > local_today { max_parsed } else { local_today };

        // Group by date.
        let mut grouped: std::collections::BTreeMap<NaiveDate, Vec<DailyUsage>> =
            std::collections::BTreeMap::new();
        for (date, entry) in parsed {
            grouped.entry(date).or_default().push(entry);
        }

        (0..7)
            .filter_map(|offset| {
                let date = end_day - Duration::days(6 - offset as i64);
                let values = grouped.get(&date).cloned().unwrap_or_default();
                let amount: Decimal = values
                    .iter()
                    .filter_map(|v| v.actual_cost.amount_decimal())
                    .sum();
                Some(DailyUsage {
                    date: date.format("%Y-%m-%d").to_string(),
                    actual_cost: Money::new(amount.to_string(), currency.clone()),
                    requests: Self::sum_integers(&values.iter().filter_map(|v| v.requests).collect::<Vec<_>>()),
                    total_tokens: Self::sum_integers(
                        &values.iter().filter_map(|v| v.total_tokens).collect::<Vec<_>>(),
                    ),
                })
            })
            .collect()
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::domain::{Account, AccountHealth, AccountSnapshot, ProviderUsageSnapshot};

    fn acc(id: &str, sort_order: i32, enabled: bool) -> Account {
        let mut a = Account::new(
            uuid::Uuid::parse_str(id).unwrap(),
            format!("Account {}", id),
            crate::domain::ProviderID::ApiInfo,
            None,
            sort_order,
        );
        a.is_enabled = enabled;
        a
    }

    #[test]
    fn disabled_accounts_excluded_from_totals_and_rows() {
        let a = acc("00000000-0000-0000-0000-000000000001", 0, true);
        let b = acc("00000000-0000-0000-0000-000000000002", 1, false);
        let now = Utc::now();
        let snap = AccountSnapshot::new(
            a.id,
            a.display_name.clone(),
            a.provider,
            a.detected_profile,
            a.low_balance_threshold,
            Some(ProviderUsageSnapshot {
                balances: vec![crate::domain::MonetaryBalance {
                    label: "balance".into(),
                    available: Money::new("100", "USD"),
                    breakdown: vec![],
                }],
                received_at: now,
                ..Default::default()
            }),
            AccountHealth::Healthy,
            Some(now),
        );
        let agg = SnapshotAggregator::aggregate(&[a, b], &[snap], now);
        assert_eq!(agg.accounts.len(), 1);
        assert_eq!(agg.balances.len(), 1);
        assert_eq!(agg.balances[0].amount, "100");
    }

    #[test]
    fn mixed_currency_does_not_combine() {
        let now = Utc::now();
        let a_id = uuid::Uuid::new_v4();
        let b_id = uuid::Uuid::new_v4();
        let snap_a = AccountSnapshot::new(
            a_id,
            "a".into(),
            crate::domain::ProviderID::ApiInfo,
            None,
            None,
            Some(ProviderUsageSnapshot {
                balances: vec![crate::domain::MonetaryBalance {
                    label: "balance".into(),
                    available: Money::new("100", "USD"),
                    breakdown: vec![],
                }],
                received_at: now,
                ..Default::default()
            }),
            AccountHealth::Healthy,
            Some(now),
        );
        let snap_b = AccountSnapshot::new(
            b_id,
            "b".into(),
            crate::domain::ProviderID::ApiInfo,
            None,
            None,
            Some(ProviderUsageSnapshot {
                balances: vec![crate::domain::MonetaryBalance {
                    label: "balance".into(),
                    available: Money::new("50", "EUR"),
                    breakdown: vec![],
                }],
                received_at: now,
                ..Default::default()
            }),
            AccountHealth::Healthy,
            Some(now),
        );
        let account_a = Account::new(a_id, "a".into(), crate::domain::ProviderID::ApiInfo, None, 0);
        let account_b = Account::new(b_id, "b".into(), crate::domain::ProviderID::ApiInfo, None, 1);
        let agg = SnapshotAggregator::aggregate(
            &[account_a, account_b],
            &[snap_a, snap_b],
            now,
        );
        assert_eq!(agg.balances.len(), 2, "currencies must stay separate");
        assert_eq!(agg.balances[0].currency, "EUR");
        assert_eq!(agg.balances[1].currency, "USD");
        assert!(!agg.is_partial, "two healthy distinct-currency accounts are not partial");
    }

    #[test]
    fn int64_overflow_nulls_today_requests_and_marks_partial() {
        let now = Utc::now();
        let id_a = uuid::Uuid::new_v4();
        let id_b = uuid::Uuid::new_v4();
        let mk = |id, requests: i64| {
            AccountSnapshot::new(
                id,
                format!("snap-{id}"),
                crate::domain::ProviderID::ApiInfo,
                None,
                None,
                Some(ProviderUsageSnapshot {
                    today: Some(crate::domain::UsageCounters {
                        requests: Some(requests),
                        ..Default::default()
                    }),
                    received_at: now,
                    ..Default::default()
                }),
                AccountHealth::Healthy,
                Some(now),
            )
        };
        let snap_a = mk(id_a, i64::MAX);
        let snap_b = mk(id_b, 1);
        let acc_a = Account::new(id_a, "a".into(), crate::domain::ProviderID::ApiInfo, None, 0);
        let acc_b = Account::new(id_b, "b".into(), crate::domain::ProviderID::ApiInfo, None, 1);
        let agg = SnapshotAggregator::aggregate(&[acc_a, acc_b], &[snap_a, snap_b], now);
        assert!(agg.today_requests.is_none(), "overflow produces None");
        assert!(agg.is_partial, "overflow -> isPartial");
    }

    #[test]
    fn stale_health_marks_aggregate_partial() {
        let now = Utc::now();
        let id_a = uuid::Uuid::new_v4();
        let snap = AccountSnapshot::new(
            id_a,
            "a".into(),
            crate::domain::ProviderID::ApiInfo,
            None,
            None,
            None,
            AccountHealth::Stale(crate::domain::SnapshotFailure::Offline),
            Some(now),
        );
        let account_a = Account::new(id_a, "a".into(), crate::domain::ProviderID::ApiInfo, None, 0);
        let agg = SnapshotAggregator::aggregate(&[account_a], &[snap], now);
        assert!(agg.is_partial);
    }
}
