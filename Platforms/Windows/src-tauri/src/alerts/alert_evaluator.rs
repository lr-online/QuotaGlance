// Alert evaluator. Mirrors `Sources/QuotaGlanceCore/Alerts/AlertEvaluator.swift`.
//
// Three-layer call:
//   - `evaluate(accounts, freshSnapshots)`: batch. Mutates each account's
//     `alertEpisodeActive` in place; returns the aggregate notification list
//     and a `didChange` flag.
//   - `evaluate(account, freshSnapshot)`: single. Delegates to the third
//     layer for `healthy` / `belowThreshold`; returns `None` for stale /
//     unavailable.
//   - `evaluate(account, freshRemaining)`: pure threshold + episode logic
//     (`<=` triggers notify if episode inactive; > triggers reset if episode
//     active; otherwise `None`).
//
// I/O-free, owned-data only: all episode mutation happens through `&mut
// Account` and is therefore deterministic across the four platforms.

use std::collections::HashMap;

use rust_decimal::Decimal;
use uuid::Uuid;

use crate::domain::{Account, AccountHealth, AccountSnapshot, Money};

/// One pending notification attached to one account.
#[derive(Debug, Clone, PartialEq, serde::Serialize)]
pub struct PendingLowBalanceNotification {
    pub account: Account,
    pub remaining: Money,
}

impl PendingLowBalanceNotification {
    pub fn new(account: Account, remaining: Money) -> Self {
        Self { account, remaining }
    }
}

/// What the evaluator decided for the batch: did anything change and which
/// notifications should be delivered.
#[derive(Debug, Clone, PartialEq, Default, serde::Serialize)]
pub struct AlertBatchEvaluation {
    pub did_change: bool,
    pub notifications: Vec<PendingLowBalanceNotification>,
}

/// Per-account outcome of one threshold check.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum AlertAction {
    None,
    Notify,
    Reset,
}

/// Stateless alert evaluator. Mirrors Swift `AlertEvaluator`.
#[derive(Debug, Clone, Copy)]
pub struct AlertEvaluator;

impl AlertEvaluator {
    /// Mirror of Swift's batch entry point. Iterates accounts in input
    /// order, mutates `alert_episode_active` in place, and accumulates
    /// notifications for accounts whose episode just started.
    pub fn evaluate(
        accounts: &mut [Account],
        fresh_snapshots: &HashMap<Uuid, AccountSnapshot>,
    ) -> AlertBatchEvaluation {
        let mut did_change = false;
        let mut notifications: Vec<PendingLowBalanceNotification> = Vec::new();
        for account in accounts.iter_mut() {
            let Some(snapshot) = fresh_snapshots.get(&account.id) else {
                continue;
            };
            let Some(remaining) = snapshot.remaining() else {
                continue;
            };
            let action = Self::evaluate_single_snapshot(account, snapshot);
            if action == AlertAction::None {
                continue;
            }
            did_change = true;
            if action == AlertAction::Notify {
                notifications.push(PendingLowBalanceNotification {
                    account: account.clone(),
                    remaining: remaining.clone(),
                });
            }
        }
        AlertBatchEvaluation {
            did_change,
            notifications,
        }
    }

    /// Single-snapshot dispatch.
    pub fn evaluate_single_snapshot(
        account: &mut Account,
        fresh_snapshot: &AccountSnapshot,
    ) -> AlertAction {
        if fresh_snapshot.account_id != account.id {
            return AlertAction::None;
        }
        match &fresh_snapshot.health {
            AccountHealth::Healthy | AccountHealth::BelowThreshold => {
                Self::evaluate_threshold(account, fresh_snapshot.remaining().map(|m| &m.amount))
            }
            AccountHealth::Stale(_) | AccountHealth::Unavailable(_) => AlertAction::None,
        }
    }

    /// Pure threshold + episode logic. Amounts compared as
    /// `rust_decimal::Decimal` (exact-string parity with Swift's `Decimal`).
    pub fn evaluate_threshold(
        account: &mut Account,
        fresh_remaining: Option<&String>,
    ) -> AlertAction {
        if !account.is_enabled {
            return AlertAction::None;
        }
        let Some(threshold) = account.low_balance_threshold else {
            return AlertAction::None;
        };
        let Some(amount_str) = fresh_remaining else {
            return AlertAction::None;
        };
        let Ok(amount) = Decimal::from_str_exact(amount_str) else {
            return AlertAction::None;
        };

        if amount <= threshold {
            if account.alert_episode_active {
                return AlertAction::None;
            }
            account.alert_episode_active = true;
            return AlertAction::Notify;
        }

        if account.alert_episode_active {
            account.alert_episode_active = false;
            return AlertAction::Reset;
        }
        AlertAction::None
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::domain::{AccountHealth, AccountSnapshot, MonetaryBalance, ProviderUsageSnapshot};
    use chrono::Utc;

    fn mk_acc(id: Uuid, threshold: Option<Decimal>) -> Account {
        Account {
            id,
            display_name: "acc".into(),
            provider: crate::domain::ProviderID::ApiInfo,
            detected_profile: None,
            is_enabled: true,
            sort_order: 0,
            low_balance_threshold: threshold,
            alert_episode_active: false,
        }
    }

    fn mk_snap(id: Uuid, remaining_amount: Option<&str>, healthy: bool) -> AccountSnapshot {
        let usage = remaining_amount.map(|amt| ProviderUsageSnapshot {
            balances: vec![MonetaryBalance {
                label: "balance".into(),
                available: Money::new(amt, "USD"),
                breakdown: vec![],
            }],
            received_at: Utc::now(),
            ..Default::default()
        });
        AccountSnapshot::new(
            id,
            "snap".into(),
            crate::domain::ProviderID::ApiInfo,
            None,
            None,
            usage,
            if healthy {
                AccountHealth::Healthy
            } else {
                AccountHealth::Unavailable(crate::domain::SnapshotFailure::Offline)
            },
            Some(Utc::now()),
        )
    }

    #[test]
    fn below_threshold_starts_episode_and_notifies() {
        let id = Uuid::new_v4();
        let mut acc = mk_acc(id, Some(Decimal::from_str_exact("10").unwrap()));
        let snap = mk_snap(id, Some("5"), true);
        let mut fresh = HashMap::new();
        fresh.insert(id, snap);
        let mut batch_accounts = vec![acc.clone()];
        let result = AlertEvaluator::evaluate(&mut batch_accounts, &fresh);
        assert!(result.did_change);
        assert_eq!(result.notifications.len(), 1);
        assert_eq!(result.notifications[0].remaining.amount, "5");
        assert!(batch_accounts[0].alert_episode_active);
    }

    #[test]
    fn episode_debounces_repeat_dip() {
        let id = Uuid::new_v4();
        let mut acc = mk_acc(id, Some(Decimal::from_str_exact("10").unwrap()));
        acc.alert_episode_active = true;
        let snap = mk_snap(id, Some("5"), true);
        let mut fresh = HashMap::new();
        fresh.insert(id, snap);
        let mut batch_accounts = vec![acc];
        let result = AlertEvaluator::evaluate(&mut batch_accounts, &fresh);
        assert!(!result.did_change);
        assert!(result.notifications.is_empty());
    }

    #[test]
    fn episode_resets_on_recovery() {
        let id = Uuid::new_v4();
        let mut acc = mk_acc(id, Some(Decimal::from_str_exact("10").unwrap()));
        acc.alert_episode_active = true;
        let snap = mk_snap(id, Some("20"), true);
        let mut fresh = HashMap::new();
        fresh.insert(id, snap);
        let mut batch_accounts = vec![acc];
        let result = AlertEvaluator::evaluate(&mut batch_accounts, &fresh);
        assert!(result.did_change);
        assert!(result.notifications.is_empty());
        assert!(!batch_accounts[0].alert_episode_active);
    }

    #[test]
    fn stale_snapshot_leaves_episode_untouched() {
        let id = Uuid::new_v4();
        let mut acc = mk_acc(id, Some(Decimal::from_str_exact("10").unwrap()));
        let snap = mk_snap(id, None, false);
        let mut fresh = HashMap::new();
        fresh.insert(id, snap);
        let mut batch_accounts = vec![acc.clone()];
        let result = AlertEvaluator::evaluate(&mut batch_accounts, &fresh);
        assert!(!result.did_change);
        assert!(!batch_accounts[0].alert_episode_active);
    }

    #[test]
    fn disabled_account_never_alerts() {
        let id = Uuid::new_v4();
        let mut acc = mk_acc(id, Some(Decimal::from_str_exact("10").unwrap()));
        acc.is_enabled = false;
        let snap = mk_snap(id, Some("5"), true);
        let mut fresh = HashMap::new();
        fresh.insert(id, snap);
        let mut batch_accounts = vec![acc];
        let result = AlertEvaluator::evaluate(&mut batch_accounts, &fresh);
        assert!(!result.did_change);
    }
}
