// CredentialVault: per-machine DPAPI-encrypted API-key store. Windows-only.
// The store maps `account_id (UUID, 16 bytes)` to ciphertext bytes. Plaintext
// keys never leave the process; only ciphertext is persisted. There is no
// per-user key, no extra entropy, and the `CRYPTPROTECT_LOCAL_MACHINE`
// semantics are deliberately dropped — the file is single-user by intent
// (Windows portable single-user client). Implementation matches Swift
// `Sources/QuotaGlanceCore/Storage/KeychainStore.swift`'s
// `store(_:key:)` / `load(_:) / delete`.
//
// DPAPI is the platform equivalent of macOS Keychain / Android Keystore:
// same trust boundary (the operating system user account), same failure
// surface (cannot decrypt on another machine). Where each platform uses
// its own primitive, the rest of the engine does not care which store
// ships the bytes.

use std::collections::HashMap;
use std::io::{Read, Seek, SeekFrom};

use uuid::Uuid;

use crate::storage::path_layout::atomic_write;

#[derive(Debug, thiserror::Error)]
pub enum VaultError {
    #[error("io: {0}")]
    Io(#[from] std::io::Error),
    #[error("dpapi: {0}")]
    Dpapi(String),
    #[error("missing entry {0}")]
    Missing(Uuid),
    #[error("record corrupted")]
    Corruption,
}

/// In-memory + on-disk DPAPI-backed vault. Mutations call
/// `flush()`; load on startup; can also `refresh()` after deletes.
pub struct CredentialVault {
    path: std::path::PathBuf,
    entries: HashMap<Uuid, Vec<u8>>,
}

impl CredentialVault {
    pub fn open(path: impl Into<std::path::PathBuf>) -> Result<Self, VaultError> {
        let path = path.into();
        let entries = if path.exists() {
            let mut file = std::fs::File::open(&path)?;
            let mut buf = Vec::new();
            file.read_to_end(&mut buf)?;
            parse_blob(&buf)?
        } else {
            HashMap::new()
        };
        Ok(Self { path, entries })
    }

    pub fn set(&mut self, account_id: Uuid, api_key: &str) -> Result<(), VaultError> {
        let ciphertext = dpapi_protect(api_key.as_bytes())?;
        self.entries.insert(account_id, ciphertext);
        self.flush()
    }

    pub fn get(&self, account_id: Uuid) -> Result<String, VaultError> {
        let ciphertext = self
            .entries
            .get(&account_id)
            .ok_or(VaultError::Missing(account_id))?;
        let plaintext = dpapi_unprotect(ciphertext)?;
        String::from_utf8(plaintext).map_err(|_| VaultError::Corruption)
    }

    pub fn remove(&mut self, account_id: Uuid) -> Result<bool, VaultError> {
        let removed = self.entries.remove(&account_id).is_some();
        if removed {
            self.flush()?;
        }
        Ok(removed)
    }

    pub fn contains(&self, account_id: Uuid) -> bool {
        self.entries.contains_key(&account_id)
    }

    pub fn ids(&self) -> Vec<Uuid> {
        self.entries.keys().copied().collect()
    }

    fn flush(&self) -> Result<(), VaultError> {
        let mut buf = Vec::with_capacity(self.entries.len() * 32 + 8);
        buf.extend_from_slice(b"QGVLT01\n");
        buf.extend_from_slice(&(self.entries.len() as u32).to_le_bytes());
        for (id, ciphertext) in &self.entries {
            buf.extend_from_slice(id.as_bytes());
            buf.extend_from_slice(&(ciphertext.len() as u32).to_le_bytes());
            buf.extend_from_slice(ciphertext);
        }
        // SAFETY: we can't take ownership of PathBuf through `?` because
        // atomic_write borrows target.  Clone the path to avoid lifetimes.
        let target = self.path.clone();
        atomic_write(&target, &buf)?;
        Ok(())
    }
}

fn parse_blob(buf: &[u8]) -> Result<HashMap<Uuid, Vec<u8>>, VaultError> {
    if buf.len() < 12 || &buf[..8] != b"QGVLT01\n" {
        return Err(VaultError::Corruption);
    }
    let mut cursor = std::io::Cursor::new(&buf[8..]);
    let mut count = [0u8; 4];
    cursor.read_exact(&mut count)?;
    let count = u32::from_le_bytes(count);
    let mut out = HashMap::with_capacity(count as usize);
    for _ in 0..count {
        let mut id_bytes = [0u8; 16];
        cursor.read_exact(&mut id_bytes)?;
        let id = Uuid::from_bytes(id_bytes);
        let mut len_bytes = [0u8; 4];
        cursor.read_exact(&mut len_bytes)?;
        let len = u32::from_le_bytes(len_bytes) as usize;
        let mut payload = vec![0u8; len];
        cursor.read_exact(&mut payload)?;
        cursor.seek(SeekFrom::Current(0))?;
        out.insert(id, payload);
    }
    Ok(out)
}

#[cfg(windows)]
fn dpapi_protect(plaintext: &[u8]) -> Result<Vec<u8>, VaultError> {
    use windows::Win32::Foundation::LocalFree;
    use windows::Win32::Security::Cryptography::{CryptProtectData, CRYPT_INTEGER_BLOB};

    let blob = CRYPT_INTEGER_BLOB {
        cbData: plaintext.len() as u32,
        pbData: plaintext.as_ptr() as *mut u8,
    };
    let mut out = CRYPT_INTEGER_BLOB {
        cbData: 0,
        pbData: std::ptr::null_mut(),
    };
    unsafe {
        CryptProtectData(&blob, None, None, None, None, 0, &mut out)
            .map_err(|e| VaultError::Dpapi(format!("CryptProtectData: {e}")))?;
    }
    let slice = unsafe { std::slice::from_raw_parts(out.pbData, out.cbData as usize) };
    let protected = slice.to_vec();
    if !out.pbData.is_null() {
        unsafe { let _ = LocalFree(windows::Win32::Foundation::HLOCAL(out.pbData as *mut std::ffi::c_void)); }
    }
    Ok(protected)
}

#[cfg(windows)]
fn dpapi_unprotect(ciphertext: &[u8]) -> Result<Vec<u8>, VaultError> {
    use windows::Win32::Foundation::LocalFree;
    use windows::Win32::Security::Cryptography::{CryptUnprotectData, CRYPT_INTEGER_BLOB};

    let blob = CRYPT_INTEGER_BLOB {
        cbData: ciphertext.len() as u32,
        pbData: ciphertext.as_ptr() as *mut u8,
    };
    let mut out = CRYPT_INTEGER_BLOB {
        cbData: 0,
        pbData: std::ptr::null_mut(),
    };
    unsafe {
        CryptUnprotectData(&blob, None, None, None, None, 0, &mut out)
            .map_err(|e| VaultError::Dpapi(format!("CryptUnprotectData: {e}")))?;
    }
    let slice = unsafe { std::slice::from_raw_parts(out.pbData, out.cbData as usize) };
    let plain = slice.to_vec();
    if !out.pbData.is_null() {
        unsafe { let _ = LocalFree(windows::Win32::Foundation::HLOCAL(out.pbData as *mut std::ffi::c_void)); }
    }
    Ok(plain)
}

#[cfg(not(windows))]
fn dpapi_protect(plaintext: &[u8]) -> Result<Vec<u8>, VaultError> {
    // Non-Windows build target (used for `cargo check` on macOS/Linux CI
    // smoke runs); a bytes-for-bytes roundtrip is fine because no
    // ciphertext actually leaves the test environment.
    Ok(plaintext.to_vec())
}

#[cfg(not(windows))]
fn dpapi_unprotect(ciphertext: &[u8]) -> Result<Vec<u8>, VaultError> {
    Ok(ciphertext.to_vec())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn roundtrip_in_memory() {
        let tmp = tempdir();
        let mut vault = CredentialVault::open(tmp.path().join("credentials.bin")).unwrap();
        let id = Uuid::new_v4();
        vault.set(id, "sk-abc-123").unwrap();
        let got = vault.get(id).unwrap();
        assert_eq!(got, "sk-abc-123");
        assert!(vault.remove(id).unwrap());
        assert!(vault.get(id).is_err());
    }

    fn tempdir() -> tempfile::TempDir {
        tempfile::tempdir().unwrap()
    }
}
