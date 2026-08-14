// Preferences store. Mirrors Swift
// `Sources/QuotaGlanceCore/Storage/Preferences.swift`. Tracked fields:
//
//   - refresh_interval_minutes: 1 | 5 | 15 | 30 | 60
//   - locale: "system" | "en" | "zh-CN"
//   - notifications_enabled: bool
//   - launch_at_login: bool
//   - default_widget_target: WidgetTarget enum (`all` | `account(id)` |
//     `default_account`).
//
// `launch_at_login` is opt-in (default false) and writes a per-user
// registry entry under
// `HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Run`.
// The portable flag (env-var) is intentionally NOT a preference; it
// controls where `path_layout.rs` puts files, not the persisted config.

use serde::{Deserialize, Serialize};
use thiserror::Error;

use crate::storage::path_layout::atomic_write;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum Locale {
    #[serde(rename = "system", alias = "")]
    System,
    #[serde(rename = "en")]
    En,
    #[serde(rename = "zh-CN")]
    ZhCn,
}

impl Default for Locale {
    fn default() -> Self {
        Self::System
    }
}

impl Locale {
    pub fn resolved(self) -> &'static str {
        match self {
            Self::System => resolve_system_locale(),
            Self::En => "en",
            Self::ZhCn => "zh-CN",
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(tag = "kind", content = "account_id", rename_all = "camelCase")]
pub enum WidgetTarget {
    All,
    Account(uuid::Uuid),
    DefaultAccount,
}

impl Default for WidgetTarget {
    fn default() -> Self {
        Self::DefaultAccount
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct Preferences {
    pub refresh_interval_minutes: u32,
    pub locale: Locale,
    pub notifications_enabled: bool,
    pub launch_at_login: bool,
    pub default_widget_target: WidgetTarget,
}

impl Default for Preferences {
    fn default() -> Self {
        Self {
            refresh_interval_minutes: 15,
            locale: Locale::default(),
            notifications_enabled: true,
            launch_at_login: false,
            default_widget_target: WidgetTarget::default(),
        }
    }
}

#[derive(Debug, Error)]
pub enum PreferencesError {
    #[error("io: {0}")]
    Io(#[from] std::io::Error),
    #[error("serde: {0}")]
    Serde(#[from] serde_json::Error),
    #[error("invalid refresh interval: {0}")]
    InvalidInterval(u32),
}

const VALID_INTERVALS: &[u32] = &[1, 5, 15, 30, 60];

pub struct PreferencesStore {
    path: std::path::PathBuf,
    prefs: Preferences,
}

impl PreferencesStore {
    pub fn load_or_create(path: impl Into<std::path::PathBuf>) -> Result<Self, PreferencesError> {
        let path = path.into();
        let prefs = if path.exists() {
            let bytes = std::fs::read(&path)?;
            serde_json::from_slice(&bytes)?
        } else {
            Preferences::default()
        };
        Self::validate(&prefs)?;
        Ok(Self { path, prefs })
    }

    pub fn current(&self) -> &Preferences {
        &self.prefs
    }

    pub fn update(&mut self, new_prefs: Preferences) -> Result<(), PreferencesError> {
        Self::validate(&new_prefs)?;
        self.prefs = new_prefs;
        self.flush()
    }

    fn flush(&self) -> Result<(), PreferencesError> {
        let bytes = serde_json::to_vec_pretty(&self.prefs)?;
        let target = self.path.clone();
        atomic_write(&target, &bytes)?;
        Ok(())
    }

    fn validate(prefs: &Preferences) -> Result<(), PreferencesError> {
        if !VALID_INTERVALS.contains(&prefs.refresh_interval_minutes) {
            return Err(PreferencesError::InvalidInterval(
                prefs.refresh_interval_minutes,
            ));
        }
        Ok(())
    }
}

fn resolve_system_locale() -> &'static str {
    // Best-effort probe of `LANG` / `LC_ALL`. The real cross-platform
    // frontend still resolves user language directly; this is the
    // preferred path for callers that want a single string during
    // pre-rendering.
    if let Ok(lang) = std::env::var("LANG") {
        if lang.to_ascii_lowercase().contains("zh") {
            return "zh-CN";
        }
        if lang.to_ascii_lowercase().contains("en") {
            return "en";
        }
    }
    if let Ok(lang) = std::env::var("LC_ALL") {
        if lang.to_ascii_lowercase().contains("zh") {
            return "zh-CN";
        }
    }
    "en"
}

#[cfg(test)]
mod tests {
    use super::*;
    use tempfile::TempDir;

    #[test]
    fn default_matches_spec() {
        let prefs = Preferences::default();
        assert_eq!(prefs.refresh_interval_minutes, 15);
        assert_eq!(prefs.locale, Locale::System);
        assert!(prefs.notifications_enabled);
        assert!(!prefs.launch_at_login);
    }

    #[test]
    fn round_trip_persists() {
        let dir = TempDir::new().unwrap();
        let path = dir.path().join("preferences.json");
        let mut store = PreferencesStore::load_or_create(&path).unwrap();
        let mut new_prefs = store.current().clone();
        new_prefs.refresh_interval_minutes = 5;
        new_prefs.locale = Locale::ZhCn;
        store.update(new_prefs).unwrap();
        let reload = PreferencesStore::load_or_create(&path).unwrap();
        assert_eq!(reload.current().refresh_interval_minutes, 5);
        assert_eq!(reload.current().locale, Locale::ZhCn);
    }

    #[test]
    fn rejects_invalid_interval() {
        let dir = TempDir::new().unwrap();
        let path = dir.path().join("preferences.json");
        let mut store = PreferencesStore::load_or_create(&path).unwrap();
        let mut new_prefs = store.current().clone();
        new_prefs.refresh_interval_minutes = 7;
        assert!(matches!(
            store.update(new_prefs),
            Err(PreferencesError::InvalidInterval(7))
        ));
    }

    #[test]
    fn launch_at_login_default_false_until_changed() {
        let dir = TempDir::new().unwrap();
        let mut store =
            PreferencesStore::load_or_create(dir.path().join("preferences.json")).unwrap();
        assert!(!store.current().launch_at_login);
        let mut prefs = store.current().clone();
        prefs.launch_at_login = true;
        store.update(prefs).unwrap();
        let reload =
            PreferencesStore::load_or_create(dir.path().join("preferences.json")).unwrap();
        assert!(reload.current().launch_at_login);
    }
}
