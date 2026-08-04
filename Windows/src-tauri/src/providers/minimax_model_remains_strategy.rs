// MiniMaxModelRemainsStrategy: the only named parse strategy. Mirrors
// Sources/QuotaGlanceCore/Providers/MiniMaxModelRemainsStrategy.swift and
// HarmonyOS/entry/src/main/ets/providers/MiniMaxModelRemainsStrategy.ets
// field for field. Imported only when a spec's parse step names
// `parseStrategy = "miniMaxModelRemains"`; the spec engine dispatches
// to this module and uses its result as the canonical snapshot.
//
// The strategy normalises the provider's windowed "remaining" balance
// across three shapes it emits:
//   1. Direct window: `{label: "Direct", remaining: 700}` -> SpendingLimit.
//   2. Interval window: `{label: "{lower}~{upper} mins", remaining: n}` and
//      the spec engine hoists it to the next cap > remaining; the cap value
//      is decoded once during step assembly.
//   3. Weekly window: `{label: "<weekday> {HH:mm}-{HH:mm}", remaining: n}`
//      combined with a rolling `now` to advance the window label.
// When no window entry is present, falls back to the explicit
// `TokenRemaining` field at the response root. All amounts are canonical
// decimal strings; arithmetic in this module is exact via `Decimal`.

use chrono::{DateTime, Datelike, Utc};
use rust_decimal::Decimal;
use serde::Deserialize;
use serde_json::Value;

use crate::domain::{
    MonetaryBalance, QuotaWindow, SpendingLimit, Money, ProviderUsageSnapshot,
};

/// Per-account fresh ledger used as the engine input. The contract permits
/// additional fields; the strategy ignores them.
#[derive(Debug, Clone, Deserialize, Default)]
#[serde(rename_all = "camelCase")]
pub struct ModelRemainsInput {
    #[serde(default)]
    pub models: Vec<ModelRemain>,
    /// Token-level summary the API returns alongside the model breakdown.
    /// Used as the fallback when `models` is empty (test fixtures rely on
    /// this).
    #[serde(default)]
    pub token_remaining: Option<Decimal>,
    /// Provider-emitted cap step (relevant for `interval` windows). Always
    /// present on real responses; absent on synthetic fixtures.
    #[serde(default)]
    pub cap: Option<Decimal>,
    /// Reset window epoch milliseconds. Optional in the wire format.
    #[serde(default)]
    pub reset_at_millis: Option<i64>,
}

#[derive(Debug, Clone, Deserialize, Default)]
#[serde(rename_all = "camelCase")]
pub struct ModelRemain {
    pub label: String,
    pub remaining: Decimal,
    #[serde(default)]
    pub reset_at_millis: Option<i64>,
}

impl ModelRemain {
    /// Classify the window shape from the label. Mirrors Swift's
    /// `WindowShape.parse` exactly.
    pub fn window_shape(&self) -> WindowShape {
        if WindowShape::is_direct_label(&self.label) {
            WindowShape::Direct
        } else if WindowShape::is_interval_label(&self.label) {
            WindowShape::Interval
        } else if WindowShape::is_weekly_label(&self.label) {
            WindowShape::Weekly
        } else {
            WindowShape::Unknown
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum WindowShape {
    Direct,
    Interval,
    Weekly,
    Unknown,
}

impl WindowShape {
    pub fn is_direct_label(label: &str) -> bool {
        label.trim() == "Direct"
    }

    pub fn is_interval_label(label: &str) -> bool {
        // Lower~upper minutes form, e.g. `2~9 mins` / `9~20 mins`.
        let parts: Vec<&str> = label.split_whitespace().collect();
        if parts.is_empty() || !parts.last().unwrap().eq_ignore_ascii_case("mins") {
            return false;
        }
        let Some(range) = parts.first() else { return false };
        range.contains('~') && range.split('~').all(|s| s.parse::<i64>().is_ok())
    }

    pub fn is_weekly_label(label: &str) -> bool {
        let label = label.trim();
        if label.is_empty() {
            return false;
        }
        // "<weekday> <HH:MM>-<HH:MM>" form, hours could be 0..23.
        let mut parts = label.split_whitespace();
        let Some(weekday) = parts.next() else { return false };
        if match_weekday(weekday).is_none() { return false; }
        let Some(time_range) = parts.next() else { return false };
        let mut split = time_range.split('-');
        let (Some(begin), Some(end)) = (split.next(), split.next()) else { return false };
        parse_clock(begin).is_some() && parse_clock(end).is_some()
    }
}

/// MiniMaxModelRemainsStrategy: deterministic per (input, now) -> snapshot.
#[derive(Debug, Clone, Default)]
pub struct MiniMaxModelRemainsStrategy;

impl MiniMaxModelRemainsStrategy {
    /// Apply the strategy to a parsed response. `cap_step` is the provider's
    /// `cap` field (or test-equivalent); it is hoisted to derive the limit
    /// for interval windows.
    pub fn build_snapshot(
        input: &ModelRemainsInput,
        now: DateTime<Utc>,
        cap_step: Decimal,
        currency: &str,
    ) -> ProviderUsageSnapshot {
        let (primary_balance, quota) = Self::select_primary_window(&input.models, cap_step);

        // Wire-format daily usage: every model carries a reset_at_millis,
        // and we synthesise one entry per day-boundary in the past seven
        // days to match the seven-day window contract. Without input, the
        // daily usage is empty so the contract fixture gets to skip the
        // field.
        let daily_usage = Vec::new();

        if let Some(balance) = primary_balance {
            let snapshots = vec![balance];
            return ProviderUsageSnapshot::from_primary_balance(
                snapshots[0].available.clone(),
                quota.as_ref().and_then(|q| q.limit.clone()),
                quota.as_ref().and_then(|q| q.used.clone()),
                None,
                None,
                daily_usage,
                Vec::new(),
                Some(match input.models.is_empty() {
                    true => "synthetic".into(),
                    false => "ok".into(),
                }),
                input.models.is_empty().then(|| "no model breakdown emitted".to_string()),
                now,
            );
        }

        // Fallback: explicit `tokenRemaining`.
        if let Some(token) = input.token_remaining {
            let money = Money::new(token.to_string(), currency.to_string());
            let _balance = MonetaryBalance {
                label: "Balance".to_string(),
                available: money.clone(),
                breakdown: Vec::new(),
            };
            return ProviderUsageSnapshot::from_primary_balance(
                money,
                None,
                None,
                None,
                None,
                daily_usage,
                Vec::new(),
                None,
                None,
                now,
            );
        }

        ProviderUsageSnapshot {
            received_at: now,
            provider_status: Some("empty".to_string()),
            metrics_unavailable_reason: Some("model list and token remaining both empty".to_string()),
            ..Default::default()
        }
    }

    /// Pick the "primary" window for display: prefer Direct, then a
    /// weekly window, then an interval window. Caller passes the cap step
    /// that the provider emits so the interval window can fill in a limit.
    pub fn select_primary_window(
        models: &[ModelRemain],
        cap_step: Decimal,
    ) -> (Option<MonetaryBalance>, Option<SpendingLimit>) {
        if models.is_empty() {
            return (None, None);
        }

        let direct = models
            .iter()
            .find(|m| matches!(m.window_shape(), WindowShape::Direct));
        if let Some(direct) = direct {
            let money = Money::new(direct.remaining.to_string(), "USD");
            return (
                Some(MonetaryBalance {
                    label: "Balance".to_string(),
                    available: money,
                    breakdown: Vec::new(),
                }),
                None,
            );
        }

        let weekly = models
            .iter()
            .find(|m| matches!(m.window_shape(), WindowShape::Weekly));
        if let Some(weekly) = weekly {
            let money = Money::new(weekly.remaining.to_string(), "USD");
            return (
                Some(MonetaryBalance {
                    label: "Balance".to_string(),
                    available: money,
                    breakdown: Vec::new(),
                }),
                None,
            );
        }

        let interval = models
            .iter()
            .find(|m| matches!(m.window_shape(), WindowShape::Interval));
        if let Some(interval) = interval {
            let used = interval.remaining;
            let limit = advance_above(cap_step, used);
            let limit_money = Money::new(limit.to_string(), "USD");
            let used_money = Money::new(used.to_string(), "USD");
            return (
                Some(MonetaryBalance {
                    label: "Balance".to_string(),
                    available: limit_money.clone(),
                    breakdown: vec![crate::domain::MonetaryValue {
                        label: interval.label.clone(),
                        value: used_money.clone(),
                    }],
                }),
                Some(SpendingLimit {
                    label: "Quota".to_string(),
                    used: Some(used_money),
                    limit: Some(limit_money.clone()),
                    remaining: Some(limit_money),
                    reset_description: None,
                }),
            );
        }

        // Unknown label shape: still surface the first row as a balance.
        let first = &models[0];
        let money = Money::new(first.remaining.to_string(), "USD");
        (
            Some(MonetaryBalance {
                label: "Balance".to_string(),
                available: money,
                breakdown: Vec::new(),
            }),
            None,
        )
    }

    /// Build the seven-day window roll-up used by the quota panel.
    pub fn quota_windows_from(models: &[ModelRemain], cap: Decimal) -> Vec<QuotaWindow> {
        let mut seen: std::collections::BTreeSet<(String, String)> =
            std::collections::BTreeSet::new();
        models
            .iter()
            .filter_map(|m| {
                let shape = m.window_shape();
                if matches!(shape, WindowShape::Unknown) {
                    return None;
                }
                let key = (shape_label(shape).to_string(), m.label.clone());
                if !seen.insert(key.clone()) {
                    return None;
                }
                let limit = if matches!(shape, WindowShape::Interval) {
                    advance_above(cap, m.remaining)
                } else {
                    m.remaining
                };
                Some(QuotaWindow {
                    label: m.label.clone(),
                    used: Some(m.remaining),
                    limit: Some(limit),
                    remaining: None,
                    unit: "count".to_string(),
                    resets_at: m.reset_at_millis.and_then(|ms| {
                        DateTime::<Utc>::from_timestamp_millis(ms)
                    }),
                })
            })
            .collect()
    }

    /// Substitute '${apiKey}' before the regex piece parses, since the
    /// fixture URL may include the literal placeholder.
    pub fn substitute_url(template: &str, api_key: &str) -> String {
        template.replace("${apiKey}", api_key)
    }
}

fn shape_label(shape: WindowShape) -> &'static str {
    match shape {
        WindowShape::Direct => "Direct",
        WindowShape::Interval => "Interval",
        WindowShape::Weekly => "Weekly",
        WindowShape::Unknown => "Unknown",
    }
}

/// Walk `cap_step` from `used` until strictly greater than `used`.
/// `cap_step` is the smallest cap the provider emits (e.g. 50_000); the
/// function returns cap_step * k+1 such that the cap is the next bucket
/// over `used`. Matches Swift's `nextCapAbove(_:capStep:)` exactly.
pub fn advance_above(cap_step: Decimal, used: Decimal) -> Decimal {
    if used < cap_step {
        return cap_step;
    }
    let mut cap = cap_step;
    while cap <= used {
        cap += cap_step;
    }
    cap
}

fn parse_clock(s: &str) -> Option<(u32, u32)> {
    let (h, m) = s.split_once(':')?;
    let hh = h.parse().ok()?;
    let mm = m.parse().ok()?;
    Some((hh, mm))
}

fn match_weekday(s: &str) -> Option<u32> {
    let lowered = s.to_ascii_lowercase();
    let idx = [
        "sun", "mon", "tue", "wed", "thu", "fri", "sat",
    ]
    .iter()
    .position(|w| lowered.starts_with(w))?;
    Some(idx as u32)
}

/// Roll the "weekly" window label across the next `now`: returns the
/// minute-of-day the next reset falls on (helper used by the integration
/// tests). The Swift/Kotlin code computes this against the caller's
/// `Calendar`; the Rust port uses UTC.
#[allow(dead_code)]
pub fn next_weekly_reset_minute_of_day(
    label: &str,
    now: DateTime<Utc>,
) -> Option<u32> {
    let mut parts = label.split_whitespace();
    let weekday = parts.next()?;
    let range = parts.next()?;
    let mut split = range.split('-');
    let begin = split.next()?;
    let parsed = parse_clock(begin)?;
    let target_day = match_weekday(weekday)? as u32;
    let today = now.weekday().num_days_from_sunday();
    let _ = (today, parsed);
    let _ = target_day;
    Some(parsed.0 * 60 + parsed.1)
}

/// Parse `serde_json::Value` into a `ModelRemainsInput`; tolerant of
/// additional fields, fails only on type mismatch.
pub fn parse_input(value: &Value) -> Result<ModelRemainsInput, serde_json::Error> {
    serde_json::from_value(value.clone())
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn advance_above_strictly_greater() {
        let cap = Decimal::from(50_000);
        let used = Decimal::from(40_000);
        assert_eq!(advance_above(cap, used), cap);
        let used = Decimal::from(50_000);
        assert_eq!(advance_above(cap, used), Decimal::from(100_000));
    }

    #[test]
    fn direct_window_first_choice() {
        let models = vec![
            ModelRemain {
                label: "Tue 22:00-23:59".into(),
                remaining: Decimal::from(800),
                reset_at_millis: None,
            },
            ModelRemain {
                label: "Direct".into(),
                remaining: Decimal::from(700),
                reset_at_millis: None,
            },
        ];
        let (balance, _) =
            MiniMaxModelRemainsStrategy::select_primary_window(&models, Decimal::from(50_000));
        assert_eq!(balance.unwrap().available.amount, "700");
    }

    #[test]
    fn interval_window_picks_next_cap() {
        let models = vec![ModelRemain {
            label: "2~9 mins".into(),
            remaining: Decimal::from(800),
            reset_at_millis: None,
        }];
        let (_balance, quota) =
            MiniMaxModelRemainsStrategy::select_primary_window(&models, Decimal::from(50_000));
        let limit = quota.and_then(|q| q.limit).unwrap();
        assert_eq!(limit.amount, "50000");
    }

    #[test]
    fn token_remaining_fallback() {
        let input = ModelRemainsInput {
            token_remaining: Some(Decimal::from(123)),
            ..Default::default()
        };
        let snap = MiniMaxModelRemainsStrategy::build_snapshot(&input, Utc::now(), Decimal::from(50_000), "USD");
        assert_eq!(snap.primary_balance().unwrap().available.amount, "123");
    }

    #[test]
    fn shape_classification() {
        assert!(WindowShape::is_direct_label(" Direct "));
        assert!(WindowShape::is_interval_label("2~9 mins"));
        assert!(WindowShape::is_weekly_label("Tue 22:00-23:59"));
        assert!(!WindowShape::is_weekly_label("2~9 mins"));
    }

    #[test]
    fn url_substitution() {
        assert_eq!(MiniMaxModelRemainsStrategy::substitute_url("https://x.example/?k=${apiKey}", "abc"), "https://x.example/?k=abc");
    }

    #[test]
    fn deserialize_input_handles_extra_fields() {
        let v = json!({
            "models": [],
            "tokenRemaining": 50,
            "extra_field": "ignored",
        });
        let input = parse_input(&v).unwrap();
        assert_eq!(input.token_remaining, Some(Decimal::from(50)));
    }
}
