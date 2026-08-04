// SnapshotStore: per-account persistence of `AccountSnapshot`. Mirrors Swift
// `Sources/QuotaGlanceCore/Storage/SnapshotStore.swift`. Saves one file per
// account under the `snapshots/` directory; deletes on account removal.
//
// Failures are recorded with `stale|unavailable` health + last failure
// reason; the refresh coordinator writes whatever snapshot the spec engine
// produces (success or failure). Receiving a `SnapshotFailure` is what the
// `assess_health` helper in `spec_driven_provider.rs` translates into the
// platform-neutral `AccountHealth` enum.

use std::fs;
use std::path::PathBuf;

use thiserror::Error;
use uuid::Uuid;

use crate::domain::AccountSnapshot;
use crate::storage::path_layout::PathLayout;

#[derive(Debug, Error)]
pub enum SnapshotStoreError {
    #[error("io: {0}")]
    Io(#[from] std::io::Error),
    #[error("serde: {0}")]
    Serde(#[from] serde_json::Error),
}

pub struct SnapshotStore {
    root: PathBuf,
}

impl SnapshotStore {
    pub fn new(layout: &PathLayout) -> Self {
        Self { root: layout.snapshots.clone() }
    }

    pub fn save(&self, snapshot: &AccountSnapshot) -> Result<(), SnapshotStoreError> {
        let bytes = serde_json::to_vec_pretty(snapshot)?;
        let target = self.path_for(snapshot.account_id);
        crate::storage::path_layout::atomic_write(&target, &bytes)?;
        Ok(())
    }

    pub fn load(&self, account_id: Uuid) -> Result<Option<AccountSnapshot>, SnapshotStoreError> {
        let path = self.path_for(account_id);
        if !path.exists() {
            return Ok(None);
        }
        let bytes = fs::read(&path)?;
        let snapshot = serde_json::from_slice(&bytes)?;
        Ok(Some(snapshot))
    }

    pub fn load_all(&self) -> Result<Vec<AccountSnapshot>, SnapshotStoreError> {
        let mut out = Vec::new();
        for entry in fs::read_dir(&self.root)? {
            let entry = entry?;
            let path = entry.path();
            if path.extension().and_then(|s| s.to_str()) != Some("json") {
                continue;
            }
            let bytes = fs::read(&path)?;
            let snapshot: AccountSnapshot = serde_json::from_slice(&bytes)?;
            out.push(snapshot);
        }
        Ok(out)
    }

    pub fn delete(&self, account_id: Uuid) -> Result<(), SnapshotStoreError> {
        let path = self.path_for(account_id);
        if path.exists() {
            fs::remove_file(&path)?;
        }
        Ok(())
    }

    fn path_for(&self, account_id: Uuid) -> PathBuf {
        self.root.join(format!("{account_id}.json"))
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::domain::{
        Account, AccountHealth, MonetaryBalance, Money, ProviderID, ProviderUsageSnapshot,
    };
    use chrono::Utc;
    use tempfile::TempDir;

    fn layout_in_tmp() -> (TempDir, PathLayout) {
        let dir = TempDir::new().unwrap();
        let root = dir.path().join("snapshots");
        fs::create_dir_all(&root).unwrap();
        let layout = PathLayout {
            root: dir.path().to_path_buf(),
            accounts: dir.path().join("accounts.json"),
            snapshots: root,
            preferences: dir.path().join("preferences.json"),
            credentials: dir.path().join("credentials.bin"),
        };
        (dir, layout)
    }

    fn snap(id: Uuid) -> AccountSnapshot {
        AccountSnapshot::new(
            id,
            "acc".into(),
            ProviderID::ApiInfo,
            None,
            None,
            Some(ProviderUsageSnapshot {
                balances: vec![MonetaryBalance {
                    label: "balance".into(),
                    available: Money::new("100", "USD"),
                    breakdown: vec![],
                }],
                received_at: Utc::now(),
                ..Default::default()
            }),
            AccountHealth::Healthy,
            Some(Utc::now()),
        )
    }

    #[test]
    fn save_load_round_trip() {
        let (dir, layout) = layout_in_tmp();
        let store = SnapshotStore::new(&layout);
        let id = Uuid::new_v4();
        store.save(&snap(id)).unwrap();
        let loaded = store.load(id).unwrap().unwrap();
        assert_eq!(loaded.account_id, id);
        assert_eq!(loaded.display_name, "acc");
        let _ = dir;
    }

    #[test]
    fn delete_makes_load_return_none() {
        let (_dir, layout) = layout_in_tmp();
        let store = SnapshotStore::new(&layout);
        let id = Uuid::new_v4();
        store.save(&snap(id)).unwrap();
        store.delete(id).unwrap();
        assert!(store.load(id).unwrap().is_none());
    }

    #[test]
    fn account_to_snapshot_helper_consistency() {
        // The AccountSnapshot carries display_name + provider; ensure the
        // round trip preserves the fields.
        let (_dir, layout) = layout_in_tmp();
        let store = SnapshotStore::new(&layout);
        let id = Uuid::new_v4();
        let s = snap(id);
        store.save(&s).unwrap();
        let loaded = store.load(id).unwrap().unwrap();
        assert!(matches!(loaded.provider, ProviderID::ApiInfo));
        let _ = Account::new(
            id,
            "acc".into(),
            ProviderID::ApiInfo,
            None,
            0,
        );
    }
}
