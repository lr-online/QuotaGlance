// Tauri 2 main-process entry. Wires plugins, tray, deep-link, single-instance,
// and the AppState used by the command surface in commands.rs.

use std::sync::{Arc, Mutex};
use std::time::Duration;

use tauri::{Emitter, Manager, WindowEvent};
use tauri_plugin_deep_link::DeepLinkExt;

pub mod aggregation;
pub mod alerts;
pub mod commands;
pub mod domain;
pub mod providers;
pub mod refresh;
pub mod storage;
pub mod tray;

use crate::commands::AppState;
use crate::providers::contract_provider::provider_catalog;
use crate::providers::http_client::ReqwestHttpClient;
use crate::refresh::refresh_coordinator::RefreshCoordinator;
use crate::storage::account_store::AccountStore;
use crate::storage::credential_vault::CredentialVault;
use crate::storage::path_layout::PathLayout;
use crate::storage::preferences::PreferencesStore;
use crate::storage::snapshot_store::SnapshotStore;

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
        .plugin(tauri_plugin_single_instance::init(
            |app: &tauri::AppHandle, _args: Vec<String>, _cwd: String| {
                // Forward deep-link arguments via embedded URL.
                if let Some(url) = _args.first() {
                    crate::commands::emit_intent(app, url.to_string());
                }
                if let Some(window) = app.get_webview_window("main") {
                    let _ = window.unminimize();
                    let _ = window.show();
                    let _ = window.set_focus();
                }
            },
        ))
        .plugin(tauri_plugin_notification::init())
        .plugin(tauri_plugin_store::Builder::default().build())
        .plugin(tauri_plugin_deep_link::init())
        .setup(|app| {
            #[cfg(any(target_os = "windows", target_os = "linux"))]
            {
                let _ = app.deep_link().register("quotaglance");
            }

            // Storage layer.
            let layout = PathLayout::new().expect("resolve path layout");
            let accounts_store =
                AccountStore::load_or_create(&layout.accounts).expect("load account store");
            let snapshots = Arc::new(SnapshotStore::new(&layout));
            let vault = CredentialVault::open(&layout.credentials).expect("open credential vault");
            let preferences =
                PreferencesStore::load_or_create(&layout.preferences).expect("load preferences");

            // Provider registry.
            let accounts = Arc::new(Mutex::new(accounts_store));
            let transport = Arc::new(ReqwestHttpClient::new().expect("create HTTP transport"));
            let providers =
                Arc::new(provider_catalog(transport).expect("load provider contract catalog"));
            let coordinator = Arc::new(RefreshCoordinator::new(
                providers,
                accounts.clone(),
                snapshots.clone(),
            ));
            let vault = Arc::new(Mutex::new(vault));
            let preferences = Arc::new(Mutex::new(preferences));

            app.manage(tray::IntentPayload(Mutex::new(None)));
            app.manage(AppState {
                coordinator: coordinator.clone(),
                accounts,
                snapshots,
                vault: vault.clone(),
                preferences: preferences.clone(),
            });

            tray::build(app.handle())?;

            // Closing a window is a hide-to-tray action. The explicit tray
            // Quit command remains the only normal way to terminate the
            // process, so refresh and notifications continue in the tray.
            for label in ["main", "tray-popover", "widget"] {
                if let Some(window) = app.get_webview_window(label) {
                    let window_for_handler = window.clone();
                    window.on_window_event(move |event| {
                        if let WindowEvent::CloseRequested { api, .. } = event {
                            api.prevent_close();
                            let _ = window_for_handler.hide();
                        }
                    });
                }
            }

            start_background_refresh(app.handle().clone(), coordinator, vault, preferences);

            if let Some(main) = app.get_webview_window("main") {
                let _ = main.show();
                let _ = main.set_focus();
            }
            Ok(())
        })
        .invoke_handler(tauri::generate_handler![
            crate::commands::list_accounts,
            crate::commands::get_account_snapshot,
            crate::commands::get_aggregate_snapshot,
            crate::commands::add_account,
            crate::commands::detect_provider_profile,
            crate::commands::update_account,
            crate::commands::delete_account,
            crate::commands::replace_account_credential,
            crate::commands::refresh_all,
            crate::commands::refresh_account,
            crate::commands::get_preferences,
            crate::commands::update_preferences,
            crate::commands::evaluate_alerts,
            crate::commands::open_window_by_label,
            crate::commands::show_notification,
            crate::commands::quit_app,
            crate::commands::get_intent_payload,
        ])
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}

/// Keep refresh, alert evaluation, and native notifications alive while all
/// WebView windows are hidden. The interval is read before every cycle so a
/// settings change takes effect without restarting the process.
fn start_background_refresh(
    app: tauri::AppHandle,
    coordinator: Arc<RefreshCoordinator>,
    vault: Arc<Mutex<CredentialVault>>,
    preferences: Arc<Mutex<PreferencesStore>>,
) {
    tauri::async_runtime::spawn(async move {
        loop {
            let results = coordinator
                .refresh_all(&|id| vault.lock().ok().and_then(|vault| vault.get(id).ok()))
                .await;
            let fresh = results
                .iter()
                .filter_map(|(_, result)| result.as_ref().ok().cloned())
                .collect();
            let alerts = coordinator.evaluate_alerts(fresh);
            let notifications_enabled = preferences
                .lock()
                .map(|store| store.current().notifications_enabled)
                .unwrap_or(false);
            if notifications_enabled {
                crate::commands::send_alert_notifications(&app, &alerts);
            }
            let _ = app.emit("snapshots-updated", ());

            let interval_minutes = preferences
                .lock()
                .map(|store| store.current().refresh_interval_minutes)
                .unwrap_or(15);
            tokio::time::sleep(Duration::from_secs(
                u64::from(interval_minutes).saturating_mul(60),
            ))
            .await;
        }
    });
}

#[cfg(test)]
mod scaffold_tests {
    #[test]
    fn runner_compiles() {}
}
