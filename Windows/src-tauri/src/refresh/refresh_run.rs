//! Host-level refresh lifecycle. This is the single Windows seam between a
//! trigger (foreground, background, tray, or widget) and its observable
//! completion effects.

use std::sync::{Arc, Mutex};

use uuid::Uuid;

use crate::alerts::{AlertBatchEvaluation, PendingLowBalanceNotification};
use crate::domain::AccountSnapshot;
use crate::refresh::refresh_coordinator::{RefreshCoordinator, RefreshError};
use crate::storage::account_store::AccountStore;

pub type CredentialResolver = Arc<dyn Fn(Uuid) -> Option<String> + Send + Sync>;

#[derive(Debug, Clone, PartialEq, Eq, serde::Serialize)]
pub struct RefreshReport {
    pub total: usize,
    pub failures: usize,
    pub last_failure_reason: Option<String>,
}

#[derive(Debug, Clone, PartialEq)]
pub struct RefreshRunOutcome {
    pub report: RefreshReport,
    pub alerts: AlertBatchEvaluation,
}

/// Platform adapters make notification delivery and quick-view publication
/// observable without leaking Tauri into the refresh engine.
pub trait RefreshRunEffects: Sync {
    fn deliver_notifications(&self, notifications: &[PendingLowBalanceNotification]);
    fn invalidate_presentation(&self);
}

pub struct RefreshRun {
    coordinator: Arc<RefreshCoordinator>,
    accounts: Arc<Mutex<AccountStore>>,
    resolve_key: CredentialResolver,
}

impl RefreshRun {
    pub fn new(
        coordinator: Arc<RefreshCoordinator>,
        accounts: Arc<Mutex<AccountStore>>,
        resolve_key: CredentialResolver,
    ) -> Self {
        Self { coordinator, accounts, resolve_key }
    }

    pub async fn refresh_all(
        &self,
        notifications_enabled: bool,
        effects: &dyn RefreshRunEffects,
    ) -> RefreshRunOutcome {
        let results = self.coordinator.refresh_all(&*self.resolve_key).await;
        self.complete(results, notifications_enabled, effects)
    }

    pub async fn refresh_account(
        &self,
        id: Uuid,
        notifications_enabled: bool,
        effects: &dyn RefreshRunEffects,
    ) -> Result<AccountSnapshot, String> {
        let account = self
            .accounts
            .lock()
            .map_err(|_| "accounts lock poisoned".to_string())?
            .find(id)
            .cloned()
            .ok_or_else(|| format!("account {id} not found"))?;
        if !account.is_enabled {
            return Err(format!("account {id} is disabled"));
        }

        let result = self
            .coordinator
            .refresh_one(account, |account_id| (self.resolve_key)(account_id))
            .await;
        let response = result
            .as_ref()
            .map(|snapshot| snapshot.clone())
            .map_err(|error| format!("refresh: {error}"));
        self.complete(vec![(id, result)], notifications_enabled, effects);
        response
    }

    fn complete(
        &self,
        results: Vec<(Uuid, Result<AccountSnapshot, RefreshError>)>,
        notifications_enabled: bool,
        effects: &dyn RefreshRunEffects,
    ) -> RefreshRunOutcome {
        let total = results.len();
        let failures = results.iter().filter(|(_, result)| result.is_err()).count();
        let last_failure_reason = results
            .iter()
            .find_map(|(_, result)| result.as_ref().err().map(|error| format!("{error}")));
        let fresh = results
            .iter()
            .filter_map(|(_, result)| result.as_ref().ok().cloned())
            .collect();
        let alerts = if fresh.is_empty() {
            AlertBatchEvaluation::default()
        } else {
            self.coordinator.evaluate_alerts(fresh)
        };
        if notifications_enabled {
            effects.deliver_notifications(&alerts.notifications);
        }
        // A completed run publishes once, including an all-failed or empty run.
        effects.invalidate_presentation();
        RefreshRunOutcome {
            report: RefreshReport { total, failures, last_failure_reason },
            alerts,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::collections::HashMap;
    use std::sync::atomic::{AtomicUsize, Ordering};
    use tempfile::TempDir;

    use crate::providers::usage_provider::UsageProvider;
    use crate::storage::path_layout::PathLayout;
    use crate::storage::snapshot_store::SnapshotStore;

    struct RecordingEffects {
        invalidations: AtomicUsize,
        notifications: AtomicUsize,
    }

    impl RefreshRunEffects for RecordingEffects {
        fn deliver_notifications(&self, notifications: &[PendingLowBalanceNotification]) {
            self.notifications.fetch_add(notifications.len(), Ordering::SeqCst);
        }

        fn invalidate_presentation(&self) {
            self.invalidations.fetch_add(1, Ordering::SeqCst);
        }
    }

    fn empty_run() -> RefreshRun {
        let dir = TempDir::new().unwrap();
        let root = dir.keep();
        let layout = PathLayout {
            root: root.clone(),
            accounts: root.join("accounts.json"),
            snapshots: root.join("snapshots"),
            preferences: root.join("preferences.json"),
            credentials: root.join("credentials.bin"),
        };
        std::fs::create_dir_all(&layout.snapshots).unwrap();
        let accounts = Arc::new(Mutex::new(AccountStore::load_or_create(&layout.accounts).unwrap()));
        let providers: Arc<HashMap<crate::domain::ProviderID, Arc<dyn UsageProvider>>> = Arc::new(HashMap::new());
        let coordinator = Arc::new(RefreshCoordinator::new(
            providers,
            accounts.clone(),
            Arc::new(SnapshotStore::new(&layout)),
        ));
        RefreshRun::new(coordinator, accounts, Arc::new(|_| None))
    }

    fn failed_single_account_run() -> (RefreshRun, Uuid) {
        let dir = TempDir::new().unwrap();
        let root = dir.keep();
        let layout = PathLayout {
            root: root.clone(),
            accounts: root.join("accounts.json"),
            snapshots: root.join("snapshots"),
            preferences: root.join("preferences.json"),
            credentials: root.join("credentials.bin"),
        };
        std::fs::create_dir_all(&layout.snapshots).unwrap();
        let id = Uuid::new_v4();
        let mut store = AccountStore::load_or_create(&layout.accounts).unwrap();
        store.add(crate::domain::Account::new(
            id,
            "failing account".into(),
            crate::domain::ProviderID::ApiInfo,
            None,
            0,
        )).unwrap();
        let accounts = Arc::new(Mutex::new(store));
        let providers: Arc<HashMap<crate::domain::ProviderID, Arc<dyn UsageProvider>>> = Arc::new(HashMap::new());
        let coordinator = Arc::new(RefreshCoordinator::new(
            providers,
            accounts.clone(),
            Arc::new(SnapshotStore::new(&layout)),
        ));
        (RefreshRun::new(coordinator, accounts, Arc::new(|_| None)), id)
    }

    #[tokio::test]
    async fn completed_empty_run_invalidates_presentation_once() {
        let effects = RecordingEffects {
            invalidations: AtomicUsize::new(0),
            notifications: AtomicUsize::new(0),
        };
        let outcome = empty_run().refresh_all(true, &effects).await;

        assert_eq!(outcome.report.total, 0);
        assert_eq!(effects.invalidations.load(Ordering::SeqCst), 1);
        assert_eq!(effects.notifications.load(Ordering::SeqCst), 0);
    }

    #[tokio::test]
    async fn failed_single_account_run_invalidates_presentation_once_without_notifications() {
        let effects = RecordingEffects {
            invalidations: AtomicUsize::new(0),
            notifications: AtomicUsize::new(0),
        };
        let (run, id) = failed_single_account_run();

        assert!(run.refresh_account(id, true, &effects).await.is_err());
        assert_eq!(effects.invalidations.load(Ordering::SeqCst), 1);
        assert_eq!(effects.notifications.load(Ordering::SeqCst), 0);
    }
}
