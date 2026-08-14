// RefreshCoordinator: per-account detect+fetch loop. Mirrors Swift
// Sources/QuotaGlanceCore/Refresh/RefreshCoordinator.swift.

use std::sync::Arc;
use futures::future;
use uuid::Uuid;

use crate::aggregation::SnapshotAggregator;
use crate::alerts::{AlertBatchEvaluation, AlertEvaluator};
use crate::domain::{Account, AccountHealth, AccountSnapshot, SnapshotFailure};
use crate::providers::provider_error::ProviderError;
use crate::providers::usage_provider::UsageProvider;
use crate::storage::account_store::AccountStore;
use crate::storage::snapshot_store::SnapshotStore;

#[derive(Debug, thiserror::Error)]
pub enum RefreshError {
    #[error("missingCredential")]
    MissingCredential,
    #[error("superseded")]
    Superseded,
    #[error("provider: {0}")]
    Provider(#[from] ProviderError),
    #[error("snapshot: {0}")]
    Snapshot(#[from] crate::storage::snapshot_store::SnapshotStoreError),
}

pub struct RefreshCoordinator {
    providers: Arc<std::collections::HashMap<crate::domain::ProviderID, Arc<dyn UsageProvider>>>,
    accounts: Arc<std::sync::Mutex<AccountStore>>,
    snapshots: Arc<SnapshotStore>,
}

impl RefreshCoordinator {
    fn is_current(&self, account: &Account) -> bool {
        self.accounts
            .lock()
            .ok()
            .and_then(|accounts| accounts.find(account.id).cloned())
            .is_some_and(|current| current == *account)
    }

    fn persist_failure(
        &self,
        account: &Account,
        failure: SnapshotFailure,
    ) -> Result<(), RefreshError> {
        let previous = self.snapshots.load(account.id)?;
        let snapshot = AccountSnapshot::new(
            account.id,
            account.display_name.clone(),
            account.provider,
            account.detected_profile,
            account.low_balance_threshold,
            previous.as_ref().and_then(|snapshot| snapshot.usage.clone()),
            if previous.as_ref().and_then(|snapshot| snapshot.usage.as_ref()).is_some() {
                AccountHealth::Stale(failure)
            } else {
                AccountHealth::Unavailable(failure)
            },
            previous.and_then(|snapshot| snapshot.last_success_at),
        );
        self.snapshots.save(&snapshot)
    }

    fn snapshot_failure(error: &RefreshError) -> SnapshotFailure {
        match error {
            RefreshError::MissingCredential => SnapshotFailure::MissingCredential,
            RefreshError::Superseded => SnapshotFailure::ProviderError,
            RefreshError::Provider(error) => match error {
                ProviderError::InvalidCredential => SnapshotFailure::InvalidCredential,
                ProviderError::RateLimited => SnapshotFailure::RateLimited,
                ProviderError::HttpStatus(_) => SnapshotFailure::ProviderError,
                ProviderError::InvalidResponse => SnapshotFailure::InvalidResponse,
                _ => SnapshotFailure::ProviderError,
            },
            RefreshError::Snapshot(_) => SnapshotFailure::ProviderError,
        }
    }

    fn record_failure(&self, account: &Account, error: RefreshError) -> (Uuid, Result<AccountSnapshot, RefreshError>) {
        if !self.is_current(account) {
            return (account.id, Err(RefreshError::Superseded));
        }
        let failure = Self::snapshot_failure(&error);
        match self.persist_failure(account, failure) {
            Ok(()) => (account.id, Err(error)),
            Err(persist_error) => (account.id, Err(persist_error)),
        }
    }

    pub fn new(
        providers: Arc<
            std::collections::HashMap<crate::domain::ProviderID, Arc<dyn UsageProvider>>,
        >,
        accounts: Arc<std::sync::Mutex<AccountStore>>,
        snapshots: Arc<SnapshotStore>,
    ) -> Self {
        Self {
            providers,
            accounts,
            snapshots,
        }
    }

    pub async fn refresh_one<F>(
        &self,
        account: Account,
        mut resolve_key: F,
    ) -> Result<AccountSnapshot, RefreshError>
    where
        F: FnMut(Uuid) -> Option<String>,
    {
        let result = async {
            let key = resolve_key(account.id).ok_or(RefreshError::MissingCredential)?;
            let provider = self
                .providers
                .get(&account.provider)
                .cloned()
                .ok_or(ProviderError::ProviderUnavailable(account.provider))?;
            let detection = provider.detect(&key).await?;
            Ok::<_, RefreshError>(detection)
        }
        .await;
        let detection = match result {
            Ok(detection) => detection,
            Err(error) => {
                let (_, failed) = self.record_failure(&account, error);
                return failed;
            }
        };
        if !self.is_current(&account) {
            return Err(RefreshError::Superseded);
        }
        let now: chrono::DateTime<chrono::Utc> = chrono::Utc::now();
        let stored = AccountSnapshot {
            account_id: account.id,
            display_name: account.display_name.clone(),
            provider: account.provider,
            detected_profile: Some(detection.profile),
            low_balance_threshold: account.low_balance_threshold,
            usage: Some(detection.snapshot),
            health: AccountHealth::Healthy,
            last_success_at: Some(now),
        };
        self.snapshots.save(&stored)?;
        Ok(stored)
    }

    pub async fn detect_profile(
        &self,
        provider_id: crate::domain::ProviderID,
        api_key: &str,
    ) -> Result<crate::domain::ProviderProfile, RefreshError> {
        let provider = self
            .providers
            .get(&provider_id)
            .ok_or(ProviderError::ProviderUnavailable(provider_id))?;
        Ok(provider.detect(api_key).await?.profile)
    }

    pub async fn refresh_all<F>(
        &self,
        resolve_key: &F,
    ) -> Vec<(Uuid, Result<AccountSnapshot, RefreshError>)>
    where
        F: Fn(Uuid) -> Option<String> + Sync,
    {
        let providers = self.providers.clone();
        let snapshots = self.snapshots.clone();
        let accounts = self.accounts.clone();
        let enabled: Vec<Account> = self
            .accounts
            .lock()
            .unwrap()
            .list()
            .iter()
            .filter(|a| a.is_enabled)
            .cloned()
            .collect();

        let futures = enabled.into_iter().map(|account| {
            let provider = providers.get(&account.provider).cloned();
            let snapshots = snapshots.clone();
            let accounts = accounts.clone();
            async move {
                let id = account.id;
                let api_key = resolve_key(id).unwrap_or_default();
                if api_key.is_empty() {
                    return self.record_failure(&account, RefreshError::MissingCredential);
                }
                let provider = match provider {
                    Some(p) => p,
                    None => {
                        let err = RefreshError::Provider(ProviderError::ProviderUnavailable(
                            account.provider,
                        ));
                        return self.record_failure(&account, err);
                    }
                };
                let result = provider.detect(&api_key).await.map_err(RefreshError::from);
                match result {
                    Ok(detection) => {
                        let is_current = accounts
                            .lock()
                            .ok()
                            .and_then(|accounts| accounts.find(id).cloned())
                            .is_some_and(|current| current == account);
                        if !is_current {
                            return (id, Err(RefreshError::Superseded));
                        }
                        let now = chrono::Utc::now();
                        let stored = AccountSnapshot {
                            account_id: id,
                            display_name: account.display_name.clone(),
                            provider: account.provider,
                            detected_profile: Some(detection.profile),
                            low_balance_threshold: account.low_balance_threshold,
                            usage: Some(detection.snapshot),
                            health: AccountHealth::Healthy,
                            last_success_at: Some(now),
                        };
                        if let Err(e) = snapshots.save(&stored) {
                            (id, Err(RefreshError::Snapshot(e)))
                        } else {
                            (id, Ok(stored))
                        }
                    }
                    Err(e) => self.record_failure(&account, e),
                }
            }
        });

        future::join_all(futures).await
    }

    pub fn aggregate_now(
        &self,
        now: chrono::DateTime<chrono::Utc>,
    ) -> crate::domain::AggregateSnapshot {
        let accounts: Vec<Account> = self.accounts.lock().unwrap().list().to_vec();
        let snapshots: Vec<AccountSnapshot> = self
            .snapshots
            .load_all()
            .unwrap_or_default()
            .into_iter()
            .filter(|s| {
                accounts
                    .iter()
                    .any(|a| a.id == s.account_id && a.is_enabled)
            })
            .collect();
        SnapshotAggregator::aggregate(&accounts, &snapshots, now)
    }

    pub fn evaluate_alerts(&self, fresh: Vec<AccountSnapshot>) -> AlertBatchEvaluation {
        let fresh_by_id: std::collections::HashMap<Uuid, AccountSnapshot> =
            fresh.iter().cloned().map(|s| (s.account_id, s)).collect();
        let mut accounts = self.accounts.lock().unwrap();
        let mut owned: Vec<Account> = accounts.list().to_vec();
        let evaluation = AlertEvaluator::evaluate(&mut owned, &fresh_by_id);
        for updated in owned {
            let _ = accounts.update(updated);
        }
        evaluation
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn refresh_coordinator_constructs() {
        let dir = tempfile::TempDir::new().unwrap();
        let layout = crate::storage::path_layout::PathLayout {
            root: dir.path().to_path_buf(),
            accounts: dir.path().join("accounts.json"),
            snapshots: dir.path().join("snapshots"),
            preferences: dir.path().join("preferences.json"),
            credentials: dir.path().join("credentials.bin"),
        };
        let accounts = Arc::new(std::sync::Mutex::new(
            AccountStore::load_or_create(&layout.accounts).unwrap(),
        ));
        let snapshots = Arc::new(SnapshotStore::new(&layout));
        let providers: Arc<
            std::collections::HashMap<crate::domain::ProviderID, Arc<dyn UsageProvider>>,
        > = Arc::new(std::collections::HashMap::new());
        let _coord = RefreshCoordinator::new(providers, accounts, snapshots);
    }

    #[tokio::test]
    async fn missing_credential_persists_an_unavailable_snapshot() {
        let dir = tempfile::TempDir::new().unwrap();
        let layout = crate::storage::path_layout::PathLayout {
            root: dir.path().to_path_buf(),
            accounts: dir.path().join("accounts.json"),
            snapshots: dir.path().join("snapshots"),
            preferences: dir.path().join("preferences.json"),
            credentials: dir.path().join("credentials.bin"),
        };
        std::fs::create_dir_all(&layout.snapshots).unwrap();
        let id = Uuid::new_v4();
        let account = Account::new(
            id,
            "missing key".into(),
            crate::domain::ProviderID::ApiInfo,
            None,
            0,
        );
        let accounts = Arc::new(std::sync::Mutex::new(
            AccountStore::load_or_create(&layout.accounts).unwrap(),
        ));
        let snapshots = Arc::new(SnapshotStore::new(&layout));
        let providers: Arc<
            std::collections::HashMap<crate::domain::ProviderID, Arc<dyn UsageProvider>>,
        > = Arc::new(std::collections::HashMap::new());
        let coordinator = RefreshCoordinator::new(providers, accounts, snapshots.clone());

        assert!(matches!(
            coordinator.refresh_one(account, |_| None).await,
            Err(RefreshError::MissingCredential)
        ));
        assert!(matches!(
            snapshots.load(id).unwrap().unwrap().health,
            AccountHealth::Unavailable(SnapshotFailure::MissingCredential)
        ));
    }
}
