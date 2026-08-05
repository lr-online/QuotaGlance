//! Windows notification-area icon, account menu, and deep-link state.
//!
//! The tray remains alive when application windows are hidden. Account menu
//! entries are rebuilt after account mutations so the native context menu is
//! always a current quick-view and settings entry point.

use std::sync::Mutex;

use tauri::{
    menu::{IsMenuItem, Menu, MenuEvent, MenuItem, MenuItemBuilder, PredefinedMenuItem},
    tray::{MouseButton, MouseButtonState, TrayIconBuilder, TrayIconEvent},
    AppHandle, Emitter, Manager, Runtime,
};

use crate::commands::AppState;

/// Holds the last consumed deep-link payload until the front end fetches it
/// via `get_intent_payload`. Reset to `None` after read.
pub struct IntentPayload(pub Mutex<Option<String>>);

fn menu<R: Runtime>(app: &AppHandle<R>) -> tauri::Result<Menu<R>> {
    let accounts = app
        .try_state::<AppState>()
        .map(|state| {
            state
                .accounts
                .lock()
                .map(|store| {
                    let mut accounts = store.list().to_vec();
                    accounts.sort_by_key(|account| account.sort_order);
                    accounts
                })
                .unwrap_or_default()
        })
        .unwrap_or_default();

    let account_items: Vec<MenuItem<R>> = if accounts.is_empty() {
        vec![
            MenuItemBuilder::with_id("no-accounts", "No accounts configured")
                .enabled(false)
                .build(app)?,
        ]
    } else {
        accounts
            .into_iter()
            .map(|account| {
                MenuItemBuilder::with_id(
                    format!("account:{}", account.id),
                    format!("{} ({})", account.display_name, account.provider),
                )
                .build(app)
            })
            .collect::<tauri::Result<Vec<_>>>()?
    };

    let refresh_item = MenuItemBuilder::with_id("refresh", "Refresh all").build(app)?;
    let settings_item = MenuItemBuilder::with_id("settings", "Settings").build(app)?;
    let open_item = MenuItemBuilder::with_id("open", "Open QuotaGlance").build(app)?;
    let separator_one = PredefinedMenuItem::separator(app)?;
    let separator_two = PredefinedMenuItem::separator(app)?;
    let separator_three = PredefinedMenuItem::separator(app)?;
    let quit_item = MenuItemBuilder::with_id("quit", "Quit").build(app)?;

    let mut items: Vec<&dyn IsMenuItem<R>> = Vec::with_capacity(account_items.len() + 7);
    items.extend(account_items.iter().map(|item| item as &dyn IsMenuItem<R>));
    items.push(&separator_one);
    items.push(&refresh_item);
    items.push(&separator_two);
    items.push(&open_item);
    items.push(&settings_item);
    items.push(&separator_three);
    items.push(&quit_item);
    Menu::with_items(app, &items)
}

/// Build the initial icon and native context menu.
pub fn build<R: Runtime>(app: &AppHandle<R>) -> tauri::Result<()> {
    let tray_menu = menu(app)?;
    let tray = TrayIconBuilder::with_id("main-tray")
        .tooltip("QuotaGlance")
        .icon(app.default_window_icon().cloned().unwrap_or_else(|| {
            tauri::image::Image::new_owned(
                include_bytes!("../../icons/tray-icon.png").to_vec(),
                128,
                128,
            )
        }))
        .menu(&tray_menu)
        .show_menu_on_left_click(false)
        .on_menu_event(handle_menu_event)
        .on_tray_icon_event(handle_tray_event)
        .build(app)?;
    tray.set_visible(true)?;
    Ok(())
}

/// Rebuild the menu after account add/edit/delete operations.
pub fn refresh_menu<R: Runtime>(app: &AppHandle<R>) -> tauri::Result<()> {
    if let Some(tray) = app.tray_by_id("main-tray") {
        tray.set_menu(Some(menu(app)?))?;
    }
    Ok(())
}

fn show_main<R: Runtime>(app: &AppHandle<R>, route: Option<String>) {
    if let Some(route) = route {
        crate::commands::emit_intent(app, route);
    }
    if let Some(window) = app.get_webview_window("main") {
        let _ = window.show();
        let _ = window.unminimize();
        let _ = window.set_focus();
    }
}

fn handle_menu_event<R: Runtime>(app: &AppHandle<R>, event: MenuEvent) {
    let id = event.id().as_ref();
    match id {
        "refresh" => {
            let _ = app.emit("menu-refresh-all", ());
        }
        "open" => show_main(app, None),
        "settings" => show_main(app, Some("quotaglance://settings".to_string())),
        "quit" => app.exit(0),
        account_id if account_id.starts_with("account:") => {
            let route = format!("quotaglance://account/{}", &account_id["account:".len()..]);
            show_main(app, Some(route));
        }
        _ => {}
    }
}

fn handle_tray_event<R: Runtime>(tray: &tauri::tray::TrayIcon<R>, event: TrayIconEvent) {
    let app = tray.app_handle().clone();
    if let TrayIconEvent::Click {
        button,
        button_state,
        ..
    } = event
    {
        if button_state == MouseButtonState::Up && matches!(button, MouseButton::Left) {
            if let Some(window) = app.get_webview_window("tray-popover") {
                let _ = window.show();
                let _ = window.set_focus();
            }
        }
    }
}
