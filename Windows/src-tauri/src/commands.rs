//! Tauri command surface: every callable entry point from the front end.
//!
//! Mirrors the Swift `App/ViewModelCommandBridge` patterns: a thin
//! argument/serialisation layer over the engine modules. The Rust main
//! process registers each `#[tauri::command]` here so the front end
//! invokes them via `@tauri-apps/api/core::invoke`.
//!
//! Commands are grouped:
//!   - accounts:  list, add, update, delete, refresh
//!   - snapshots: read latest, evaluate alerts
//!   - preferences: get, update
//!   - intents: deep-link payload consumed once, then a new instance path
//!   - utility: open widget, open main, show notification, quit
//!
//! The actual refresh / aggregator logic lives in
//! `crate::refresh::RefreshCoordinator`; this file is the bridge.

use std::sync::Arc;

use serde::{Deserialize, Serialize};
use tauri::{Emitter, Manager, Runtime, State};
use uuid::Uuid;

use crate::alerts::AlertBatchEvaluation;
use crate::domain::{
    Account, AccountSnapshot, AggregateSnapshot, ProviderCredentialKind, ProviderID,
    ProviderProfile, ProviderRegion,
};
use crate::refresh::refresh_coordinator::RefreshCoordinator;
pub use crate::refresh::refresh_run::RefreshReport;
use crate::refresh::refresh_run::{RefreshRun, RefreshRunEffects};
use crate::storage::account_store::AccountStore;
use crate::storage::credential_vault::CredentialVault;
use crate::storage::preferences::{Preferences, PreferencesStore};
use crate::storage::snapshot_store::SnapshotStore;

#[derive(Debug, Serialize, Deserialize)]
pub struct AddAccountRequest {
    pub display_name: String,
    pub provider: ProviderID,
    pub api_key: String,
    pub detected_profile: ProviderProfile,
    pub low_balance_threshold: Option<String>,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct UpdateAccountRequest {
    pub id: Uuid,
    pub display_name: Option<String>,
    pub detected_profile: Option<ProviderProfile>,
    pub low_balance_threshold: Option<Option<String>>,
    pub is_enabled: Option<bool>,
}

#[derive(Clone)]
pub struct AppState {
    pub coordinator: Arc<RefreshCoordinator>,
    pub refresh_run: Arc<RefreshRun>,
    pub accounts: Arc<std::sync::Mutex<AccountStore>>,
    pub snapshots: Arc<SnapshotStore>,
    pub vault: Arc<std::sync::Mutex<CredentialVault>>,
    pub preferences: Arc<std::sync::Mutex<PreferencesStore>>,
}

#[tauri::command]
pub fn list_accounts(state: State<'_, AppState>) -> Vec<Account> {
    state.accounts.lock().unwrap().list().to_vec()
}

#[tauri::command]
pub fn get_account_snapshot(
    state: State<'_, AppState>,
    id: Uuid,
) -> Result<Option<AccountSnapshot>, String> {
    state
        .snapshots
        .load(id)
        .map_err(|error| format!("snapshots: {error}"))
}

#[tauri::command]
pub fn get_aggregate_snapshot(state: State<'_, AppState>) -> AggregateSnapshot {
    state.coordinator.aggregate_now(chrono::Utc::now())
}

#[tauri::command]
pub fn add_account(
    app: tauri::AppHandle,
    state: State<'_, AppState>,
    request: AddAccountRequest,
) -> Result<Uuid, String> {
    let mut accounts = state.accounts.lock().unwrap();
    let mut vault = state.vault.lock().unwrap();
    let id = Uuid::new_v4();
    let sort_order = accounts.list().len() as i32;
    if request.api_key.trim().is_empty() {
        return Err("validation: api key must not be blank".to_string());
    }
    let mut account = Account::new(
        id,
        request.display_name,
        request.provider,
        Some(request.detected_profile),
        sort_order,
    );
    account.low_balance_threshold = request
        .low_balance_threshold
        .as_deref()
        .map(rust_decimal::Decimal::from_str_exact)
        .transpose()
        .map_err(|_| "validation: low balance threshold must be a decimal".to_string())?;
    account
        .try_validated()
        .map_err(|e| format!("validation: {e}"))?;
    accounts.add(account).map_err(|e| format!("store: {e}"))?;
    vault
        .set(id, &request.api_key)
        .map_err(|e| format!("vault: {e}"))?;
    drop(vault);
    drop(accounts);
    let _ = crate::tray::refresh_menu(&app);
    Ok(id)
}

#[tauri::command]
pub async fn detect_provider_profile(
    state: State<'_, AppState>,
    provider: ProviderID,
    api_key: String,
) -> Result<ProviderProfile, String> {
    state
        .coordinator
        .detect_profile(provider, &api_key)
        .await
        .map_err(|error| format!("detect: {error}"))
}

#[tauri::command]
pub async fn update_account(
    app: tauri::AppHandle,
    state: State<'_, AppState>,
    request: UpdateAccountRequest,
) -> Result<(), String> {
    let mut accounts = state.accounts.lock().unwrap();
    let existing = accounts
        .find(request.id)
        .cloned()
        .ok_or_else(|| format!("account {} not found", request.id))?;
    let mut updated = existing.clone();
    if let Some(name) = request.display_name {
        updated.display_name = name;
    }
    if let Some(profile) = request.detected_profile {
        updated.detected_profile = Some(profile);
    }
    if let Some(threshold_change) = request.low_balance_threshold {
        updated.low_balance_threshold = threshold_change
            .as_ref()
            .and_then(|s| rust_decimal::Decimal::from_str_exact(s).ok());
    }
    if let Some(enabled) = request.is_enabled {
        updated.is_enabled = enabled;
    }
    accounts
        .update(updated)
        .map_err(|e| format!("store: {e}"))?;
    drop(accounts);
    let _ = crate::tray::refresh_menu(&app);
    Ok(())
}

#[tauri::command]
pub fn delete_account(
    app: tauri::AppHandle,
    state: State<'_, AppState>,
    id: Uuid,
) -> Result<bool, String> {
    let mut accounts = state.accounts.lock().unwrap();
    let mut vault = state.vault.lock().unwrap();
    let removed = accounts.delete(id).map_err(|e| format!("store: {e}"))?;
    if removed.is_some() {
        vault.remove(id).map_err(|e| format!("vault: {e}"))?;
        state
            .snapshots
            .delete(id)
            .map_err(|e| format!("snapshots: {e}"))?;
        drop(vault);
        drop(accounts);
        let _ = crate::tray::refresh_menu(&app);
    }
    Ok(removed.is_some())
}

#[tauri::command]
pub async fn refresh_all(
    app: tauri::AppHandle,
    state: State<'_, AppState>,
) -> Result<RefreshReport, String> {
    let prefs = state.preferences.lock().unwrap().current().clone();
    let effects = TauriRefreshRunEffects { app };
    Ok(state
        .refresh_run
        .refresh_all(prefs.notifications_enabled, &effects)
        .await
        .report)
}

#[tauri::command]
pub fn replace_account_credential(
    state: State<'_, AppState>,
    id: Uuid,
    api_key: String,
) -> Result<(), String> {
    if api_key.trim().is_empty() {
        return Err("validation: api key must not be blank".to_string());
    }
    if state.accounts.lock().unwrap().find(id).is_none() {
        return Err(format!("account {id} not found"));
    }
    state
        .vault
        .lock()
        .unwrap()
        .set(id, &api_key)
        .map_err(|error| format!("vault: {error}"))
}

#[tauri::command]
pub async fn refresh_account(
    app: tauri::AppHandle,
    state: State<'_, AppState>,
    id: Uuid,
) -> Result<AccountSnapshot, String> {
    let notifications_enabled = state.preferences.lock().unwrap().current().notifications_enabled;
    let effects = TauriRefreshRunEffects { app };
    state
        .refresh_run
        .refresh_account(id, notifications_enabled, &effects)
        .await
}

#[tauri::command]
pub fn get_preferences(state: State<'_, AppState>) -> Preferences {
    state.preferences.lock().unwrap().current().clone()
}

#[tauri::command]
pub fn update_preferences(
    state: State<'_, AppState>,
    preferences: Preferences,
) -> Result<(), String> {
    state
        .preferences
        .lock()
        .unwrap()
        .update(preferences)
        .map_err(|e| format!("preferences: {e}"))
}

/// Deliver only newly-started low-balance episodes. The evaluator already
/// suppresses duplicate notifications and ignores stale/unavailable data.
pub fn send_alert_notifications<R: Runtime>(
    app: &tauri::AppHandle<R>,
    evaluation: &AlertBatchEvaluation,
) {
    use tauri_plugin_notification::NotificationExt;

    for pending in &evaluation.notifications {
        let title = format!("Low balance: {}", pending.account.display_name);
        let body = format!(
            "Remaining balance: {} {}",
            pending.remaining.amount, pending.remaining.currency
        );
        if let Err(error) = app.notification().builder().title(title).body(body).show() {
            tracing::warn!(%error, "could not show low-balance notification");
        }
    }
}

/// Tauri is an adapter for the refresh-run seam. It does not own lifecycle
/// policy: notifications and the one post-run presentation event are driven
/// exclusively by `RefreshRun`.
pub(crate) struct TauriRefreshRunEffects<R: Runtime> {
    pub(crate) app: tauri::AppHandle<R>,
}

impl<R: Runtime> RefreshRunEffects for TauriRefreshRunEffects<R> {
    fn deliver_notifications(&self, notifications: &[crate::alerts::PendingLowBalanceNotification]) {
        let evaluation = crate::alerts::AlertBatchEvaluation {
            did_change: !notifications.is_empty(),
            notifications: notifications.to_vec(),
        };
        send_alert_notifications(&self.app, &evaluation);
    }

    fn invalidate_presentation(&self) {
        let _ = self.app.emit("snapshots-updated", ());
    }
}

#[tauri::command]
pub fn open_window_by_label(app: tauri::AppHandle, label: String) -> Result<(), String> {
    let window = app
        .get_webview_window(&label)
        .ok_or_else(|| format!("window '{label}' not found"))?;
    window.show().map_err(|e| format!("show: {e}"))?;
    window.set_focus().map_err(|e| format!("focus: {e}"))?;
    Ok(())
}

#[tauri::command]
pub fn show_notification(app: tauri::AppHandle, title: String, body: String) -> Result<(), String> {
    use tauri_plugin_notification::NotificationExt;
    app.notification()
        .builder()
        .title(title)
        .body(body)
        .show()
        .map_err(|e| format!("notification: {e}"))
}

#[tauri::command]
pub fn quit_app(app: tauri::AppHandle) {
    app.exit(0);
}

#[tauri::command]
pub fn get_intent_payload(app: tauri::AppHandle) -> Option<String> {
    // Stored by the deep-link handler in lib.rs after a
    // `quotaglance://` URL is consumed.
    app.try_state::<crate::tray::IntentPayload>()
        .and_then(|state| state.0.lock().unwrap().take())
}

/// Take a snapshot atomically and turn the deep-link URL into an event
/// the front-end subscribes to. Pulled from lib.rs's `setup`.
pub fn emit_intent<R: Runtime>(app: &tauri::AppHandle<R>, payload: String) {
    let _ = app.emit("deep-link", payload.clone());
    if let Some(state) = app.try_state::<crate::tray::IntentPayload>() {
        *state.0.lock().unwrap() = Some(payload);
    }
}

impl Account {
    fn try_validated(&self) -> Result<(), AccountValidationError> {
        if self.display_name.trim().is_empty() {
            return Err(AccountValidationError::BlankName);
        }
        Ok(())
    }
}

#[derive(Debug, thiserror::Error)]
pub enum AccountValidationError {
    #[error("display name must not be blank")]
    BlankName,
}

/// Helper used by command tests: returns the default profile for an
/// `apiInfo` account.
pub fn api_info_profile() -> ProviderProfile {
    ProviderProfile::new(ProviderRegion::Global, ProviderCredentialKind::Standard)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn api_info_profile_is_global_standard() {
        let p = api_info_profile();
        assert!(matches!(p.region, ProviderRegion::Global));
        assert!(matches!(
            p.credential_kind,
            ProviderCredentialKind::Standard
        ));
    }
}
