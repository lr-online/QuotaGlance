// AccountStore: persistent list of `Account` rows. Mirrors Swift
// `Sources/QuotaGlanceCore/Storage/AccountStore.swift`. Atomic write
// (`temp + rename`) for partial-write safety, JSON-only (no migration
// upgrade path is required today — schema bumps land on a separate file).

use std::fs;

use thiserror::Error;
use uuid::Uuid;

use crate::domain::Account;
use crate::storage::path_layout::atomic_write;

#[derive(Debug, Error)]
pub enum StoreError {
    #[error("io: {0}")]
    Io(#[from] std::io::Error),
    #[error("serde: {0}")]
    Serde(#[from] serde_json::Error),
    #[error("validation: {0}")]
    Validation(String),
}

const MAX_ACCOUNTS: usize = 20;
const FILE_HEADER: &str = "QGAST01";

#[derive(Clone)]
pub struct AccountStore {
    path: std::path::PathBuf,
    accounts: Vec<Account>,
}

impl AccountStore {
    pub fn load_or_create(path: impl Into<std::path::PathBuf>) -> Result<Self, StoreError> {
        let path = path.into();
        let accounts = if path.exists() {
            let bytes = fs::read(&path)?;
            parse_blob(&bytes)?
        } else {
            Vec::new()
        };
        Ok(Self { path, accounts })
    }

    pub fn list(&self) -> &[Account] {
        &self.accounts
    }

    pub fn find(&self, id: Uuid) -> Option<&Account> {
        self.accounts.iter().find(|a| a.id == id)
    }

    pub fn add(&mut self, account: Account) -> Result<(), StoreError> {
        if self.accounts.len() >= MAX_ACCOUNTS {
            return Err(StoreError::Validation(format!(
                "cannot exceed {MAX_ACCOUNTS} accounts"
            )));
        }
        validate_uniqueness(&self.accounts, &account)?;
        self.accounts.push(account);
        self.flush()
    }

    pub fn update(&mut self, account: Account) -> Result<(), StoreError> {
        let id = account.id;
        validate_uniqueness_for_update(&self.accounts, &account)?;
        let Some(slot) = self.accounts.iter_mut().find(|a| a.id == id) else {
            return Err(StoreError::Validation(format!("account {id} not found")));
        };
        *slot = account;
        self.flush()
    }

    pub fn delete(&mut self, id: Uuid) -> Result<Option<Account>, StoreError> {
        let pos = self.accounts.iter().position(|a| a.id == id);
        let Some(pos) = pos else {
            return Ok(None);
        };
        let removed = self.accounts.remove(pos);
        self.flush()?;
        Ok(Some(removed))
    }

    fn flush(&self) -> Result<(), StoreError> {
        let mut buf = Vec::with_capacity(self.accounts.len() * 256 + 8);
        buf.extend_from_slice(FILE_HEADER.as_bytes());
        buf.push(b'\n');
        let body = serde_json::to_vec(&self.accounts)?;
        buf.extend_from_slice(&(body.len() as u32).to_le_bytes());
        buf.extend_from_slice(&body);
        atomic_write(&self.path, &buf)?;
        Ok(())
    }
}

fn parse_blob(buf: &[u8]) -> Result<Vec<Account>, StoreError> {
    if buf.len() < 16 || &buf[..7] != FILE_HEADER.as_bytes() || buf[7] != b'\n' {
        return Err(StoreError::Validation("missing or unknown header".into()));
    }
    let header_bytes = FILE_HEADER.len() + 1;
    let mut cursor = std::io::Cursor::new(&buf[header_bytes..]);
    let mut len_bytes = [0u8; 4];
    std::io::Read::read_exact(&mut cursor, &mut len_bytes)?;
    let len = u32::from_le_bytes(len_bytes) as usize;
    let start = header_bytes + cursor.position() as usize;
    let end = start + len;
    if end > buf.len() {
        return Err(StoreError::Validation("truncated body".into()));
    }
    let accounts: Vec<Account> = serde_json::from_slice(&buf[start..end])?;
    Ok(accounts)
}

fn validate_uniqueness(accounts: &[Account], candidate: &Account) -> Result<(), StoreError> {
    if candidate.display_name.trim().is_empty() {
        return Err(StoreError::Validation("displayName must not be blank".into()));
    }
    if accounts.iter().any(|a| a.id == candidate.id) {
        return Err(StoreError::Validation("duplicate id".into()));
    }
    let trimmed = candidate.display_name.trim();
    if accounts.iter().any(|a| a.display_name.trim() == trimmed) {
        return Err(StoreError::Validation("duplicate displayName".into()));
    }
    Ok(())
}

fn validate_uniqueness_for_update(accounts: &[Account], candidate: &Account) -> Result<(), StoreError> {
    if candidate.display_name.trim().is_empty() {
        return Err(StoreError::Validation("displayName must not be blank".into()));
    }
    let trimmed = candidate.display_name.trim();
    if accounts
        .iter()
        .any(|a| a.id != candidate.id && a.display_name.trim() == trimmed)
    {
        return Err(StoreError::Validation("duplicate displayName".into()));
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::domain::{ProviderCredentialKind, ProviderProfile, ProviderRegion};
    use tempfile::TempDir;

    fn tmp() -> TempDir {
        TempDir::new().unwrap()
    }

    fn make(provider_kind: &str) -> Account {
        Account::new(
            Uuid::new_v4(),
            format!("account {provider_kind}"),
            crate::domain::ProviderID::DeepSeek,
            Some(ProviderProfile::new(
                ProviderRegion::Global,
                ProviderCredentialKind::Standard,
            )),
            0,
        )
    }

    #[test]
    fn add_list_persist_round_trip() {
        let dir = tmp();
        let path = dir.path().join("accounts.json");
        let mut store = AccountStore::load_or_create(&path).unwrap();
        store.add(make("a")).unwrap();
        store.add(make("b")).unwrap();
        let refreshed = AccountStore::load_or_create(&path).unwrap();
        assert_eq!(refreshed.list().len(), 2);
    }

    #[test]
    fn rejects_blank_name() {
        let dir = tmp();
        let mut store = AccountStore::load_or_create(dir.path().join("accounts.json")).unwrap();
        let mut bad = make("x");
        bad.display_name = "  ".into();
        assert!(matches!(
            store.add(bad),
            Err(StoreError::Validation(_))
        ));
    }

    #[test]
    fn rejects_duplicate_name() {
        let dir = tmp();
        let mut store = AccountStore::load_or_create(dir.path().join("accounts.json")).unwrap();
        store.add(make("a")).unwrap();
        let dup = make("a");
        assert!(matches!(
            store.add(dup),
            Err(StoreError::Validation(_))
        ));
    }

    #[test]
    fn capacity_capped_at_twenty() {
        let dir = tmp();
        let mut store = AccountStore::load_or_create(dir.path().join("accounts.json")).unwrap();
        for i in 0..20 {
            let mut a = make(&format!("a{i}"));
            a.id = Uuid::new_v4();
            store.add(a).unwrap();
        }
        let mut overflow = make("x");
        overflow.display_name = "21st".into();
        assert!(matches!(
            store.add(overflow),
            Err(StoreError::Validation(_))
        ));
    }
}
