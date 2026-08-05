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
use std::time::Duration;

use serde::{Deserialize, Serialize};
use tauri::{Emitter, Manager, State};
use uuid::Uuid;

use crate::alerts::{AlertBatchEvaluation, AlertEvaluator};
use crate::domain::{Account, AccountSnapshot, AggregateSnapshot, ProviderID, ProviderProfile, ProviderRegion, ProviderCredentialKind};
use crate::refresh::refresh_coordinator::{RefreshCoordinator, RefreshError};
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

#[derive(Debug, Serialize)]
pub struct RefreshReport {
    pub total: usize,
    pub failures: usize,
    pub last_failure_reason: Option<String>,
}

#[derive(Clone)]
pub struct AppState {
    pub coordinator: Arc<RefreshCoordinator>,
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
    state.snapshots.load(id).map_err(|error| format!("snapshots: {error}"))
}

#[tauri::command]
pub fn get_aggregate_snapshot(state: State<'_, AppState>) -> AggregateSnapshot {
    state.coordinator.aggregate_now(chrono::Utc::now())
}

#[tauri::command]
pub fn add_account(state: State<'_, AppState>, request: AddAccountRequest) -> Result<Uuid, String> {
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
    accounts.update(updated).map_err(|e| format!("store: {e}"))?;
    Ok(())
}

#[tauri::command]
pub fn delete_account(state: State<'_, AppState>, id: Uuid) -> Result<bool, String> {
    let mut accounts = state.accounts.lock().unwrap();
    let mut vault = state.vault.lock().unwrap();
    let removed = accounts.delete(id).map_err(|e| format!("store: {e}"))?;
    if removed.is_some() {
        vault.remove(id).map_err(|e| format!("vault: {e}"))?;
        state.snapshots.delete(id).map_err(|e| format!("snapshots: {e}"))?;
    }
    Ok(removed.is_some())
}

#[tauri::command]
pub async fn refresh_all(state: State<'_, AppState>) -> Result<RefreshReport, String> {
    let prefs = state.preferences.lock().unwrap().current().clone();
    let vault = state.vault.clone();
    let coord = state.coordinator.clone();
    let report = coord
        .refresh_all_async(&prefs, move |id| {
            vault.lock().unwrap().get(id).ok()
        })
        .await;
    let total = report.len();
    let failures = report.iter().filter(|(_, r)| r.is_err()).count();
    let last_failure_reason = report
        .iter()
        .find_map(|(_, r)| r.as_ref().err().map(|e| format!("{e}")))
        .or_else(|| None);
    Ok(RefreshReport {
        total,
        failures,
        last_failure_reason,
    })
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
    state: State<'_, AppState>,
    id: Uuid,
) -> Result<AccountSnapshot, String> {
    let account = state
        .accounts
        .lock()
        .unwrap()
        .find(id)
        .cloned()
        .ok_or_else(|| format!("account {id} not found"))?;
    let vault = state.vault.clone();
    state
        .coordinator
        .refresh_one(account, move |account_id| vault.lock().unwrap().get(account_id).ok())
        .await
        .map_err(|error| format!("refresh: {error}"))
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

#[tauri::command]
pub fn evaluate_alerts(state: State<'_, AppState>) -> AlertBatchEvaluation {
    let fresh = state.snapshots.load_all().unwrap_or_default();
    let fresh_map: std::collections::HashMap<Uuid, crate::domain::AccountSnapshot> = fresh
        .iter()
        .cloned()
        .map(|s| (s.account_id, s))
        .collect();
    let mut owned: Vec<Account> = state.accounts.lock().unwrap().list().to_vec();
    AlertEvaluator::evaluate(&mut owned, &fresh_map)
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
pub fn show_notification(
    app: tauri::AppHandle,
    title: String,
    body: String,
) -> Result<(), String> {
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
pub fn emit_intent(app: &tauri::AppHandle, payload: String) {
    let _ = app.emit("deep-link", payload.clone());
    if let Some(state) = app.try_state::<crate::tray::IntentPayload>() {
        *state.0.lock().unwrap() = Some(payload);
    }
}

// Extension trait for RefreshCoordinator so commands can call a
// one-shot async batch with a stable signature, even though the
// underlying `refresh_all` returns Vec<(Uuid, Result<...)>`. The
// returned tuple is mapped to RefreshReport by callers.
impl RefreshCoordinator {
    pub async fn refresh_all_async(
        self: Arc<Self>,
        _prefs: &Preferences,
        resolve_key: impl Fn(Uuid) -> Option<String> + Send + Sync + 'static,
    ) -> Vec<(Uuid, Result<crate::domain::AccountSnapshot, RefreshError>)> {
        // single ticker delay to keep the event loop alive
        tokio::time::sleep(Duration::from_millis(0)).await;
        self.refresh_all(&resolve_key).await
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
        assert!(matches!(p.credential_kind, ProviderCredentialKind::Standard));
    }
}
