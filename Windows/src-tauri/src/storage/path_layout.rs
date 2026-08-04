// Path layout + atomic-write helper. Mirrors the file-system conventions of
// Swift `Sources/QuotaGlanceCore/Storage/PathLayout.swift`. All non-test
// consumers reach the OS-specific directories through `PathLayout::new()`
// so the `PORTABLE=1` env-var override applies at one point.
//
// `LOCALAPPDATA` is `%LOCALAPPDATA%\QuotaGlance\` on Windows;
// `PORTABLE=1` redirects to `<exe parent>\QuotaGlancePortable\` so the
// whole client can run from a USB stick without leaving traces on the
// host. The portable-vs-fixed choice is recorded in
// `Windows/AGENTS.md` Platform-differences allowlist.

use std::fs::File;
use std::io::Write;
use std::path::{Path, PathBuf};

#[derive(Debug, Clone)]
pub struct PathLayout {
    pub root: PathBuf,
    pub accounts: PathBuf,
    pub snapshots: PathBuf,
    pub preferences: PathBuf,
    pub credentials: PathBuf,
}

#[derive(Debug, thiserror::Error)]
pub enum PathError {
    #[error("failed to resolve LocalAppData directory: {0}")]
    NoLocalAppData(String),
    #[error("failed to create directory {0}: {1}")]
    CreateDir(PathBuf, String),
    #[error("io: {0}")]
    Io(#[from] std::io::Error),
}

impl PathLayout {
    /// Resolve the canonical layout. Reads `QUOTAGLANCE_PORTABLE` env at
    /// construction time; switch the layout by reconstructing.
    pub fn new() -> Result<Self, PathError> {
        let root = if std::env::var("QUOTAGLANCE_PORTABLE")
            .map(|v| v == "1" || v.eq_ignore_ascii_case("true"))
            .unwrap_or(false)
        {
            let exe = std::env::current_exe()?;
            let exe_dir = exe.parent().ok_or_else(|| {
                PathError::Io(std::io::Error::new(
                    std::io::ErrorKind::NotFound,
                    "executable parent missing",
                ))
            })?;
            exe_dir.join("QuotaGlancePortable")
        } else {
            // %LOCALAPPDATA%\QuotaGlance
            let local = std::env::var("LOCALAPPDATA").map_err(|_| {
                PathError::NoLocalAppData("LOCALAPPDATA environment variable missing".into())
            })?;
            PathBuf::from(local).join("QuotaGlance")
        };

        std::fs::create_dir_all(&root)
            .map_err(|e| PathError::CreateDir(root.clone(), e.to_string()))?;

        let accounts = root.join("accounts.json");
        let snapshots = root.join("snapshots");
        let preferences = root.join("preferences.json");
        let credentials = root.join("credentials.bin");
        std::fs::create_dir_all(&snapshots)
            .map_err(|e| PathError::CreateDir(snapshots.clone(), e.to_string()))?;
        Ok(Self {
            root,
            accounts,
            snapshots,
            preferences,
            credentials,
        })
    }

    /// Per-account snapshot path under `snapshots/`.
    pub fn snapshot_path_for(&self, account_id: uuid::Uuid) -> PathBuf {
        self.snapshots.join(format!("{account_id}.json"))
    }
}

/// Atomic-write helper: writes `contents` into a temp file, then renames
/// it onto `target`. Mirrors Swift `Storage/accountStore.save()`.
///
/// On rename failure the temp file is best-effort removed; the call site
/// receives `RenameFailed` so it can decide whether to retry.
pub fn atomic_write(target: &Path, contents: &[u8]) -> std::io::Result<()> {
    if let Some(parent) = target.parent() {
        std::fs::create_dir_all(parent)?;
    }
    let temp = target.with_extension("tmp");
    {
        let mut file = File::create(&temp)?;
        file.write_all(contents)?;
        file.sync_all()?;
    }
    if let Err(err) = std::fs::rename(&temp, target) {
        let _ = std::fs::remove_file(&temp);
        return Err(err);
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use tempfile::TempDir;

    #[test]
    fn atomic_write_creates_and_replaces() {
        let temp_dir = TempDir::new().unwrap();
        let target = temp_dir.path().join("foo.json");
        atomic_write(&target, b"hello").unwrap();
        assert_eq!(std::fs::read(&target).unwrap(), b"hello");
        atomic_write(&target, b"world").unwrap();
        assert_eq!(std::fs::read(&target).unwrap(), b"world");
    }

    #[test]
    fn resolve_layout_succeeds() {
        // LOCALAPPDATA is set on Windows runner; CI may set it too.
        // Skip assertion of value; ensure PathLayout::new resolves.
        let resolved = PathLayout::new();
        assert!(resolved.is_ok(), "PathLayout should resolve in current host environment");
    }
}
