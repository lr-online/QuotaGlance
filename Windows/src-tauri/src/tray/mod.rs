//! Tray icon, popover, and intent-payload state.
//!
//! Tray behaviour parity with macOS menu bar:
//!   - Left click toggles the popover window (small size, decorationless).
//!   - Right click opens a context menu: refresh all, open main window,
//!     quit.
//! Popover windows live in a dedicated WebviewWindow labelled
//! `tray-popover`; the macOS popover window is auto-positioned near the
//! tray icon — Tauri 2 does not give us a per-monitor pointer to the
//! tray, so we instead centre the popover on the primary monitor and
//! keep its `alwaysOnTop` flag set so it sits above the main window.

use std::sync::Mutex;

use tauri::{
    menu::{Menu, MenuEvent, MenuItemBuilder, PredefinedMenuItem},
    tray::{MouseButton, MouseButtonState, TrayIconBuilder, TrayIconEvent},
    AppHandle, Emitter, Manager, Runtime,
};

/// Holds the last consumed deep-link payload until the front end fetches
/// it via `get_intent_payload`. Reset to `None` after read.
pub struct IntentPayload(pub Mutex<Option<String>>);

pub fn build<R: Runtime>(app: &AppHandle<R>) -> tauri::Result<()> {
    let refresh_item = MenuItemBuilder::with_id("refresh", "Refresh all").build(app)?;
    let open_item = MenuItemBuilder::with_id("open", "Open QuotaGlance").build(app)?;
    let separator = PredefinedMenuItem::separator(app)?;
    let quit_item = MenuItemBuilder::with_id("quit", "Quit").build(app)?;
    let menu = Menu::with_items(app, &[&refresh_item, &separator, &open_item, &separator, &quit_item])?;

    let _ = TrayIconBuilder::with_id("main-tray")
        .tooltip("QuotaGlance")
        .icon(app.default_window_icon().cloned().unwrap_or_else(|| {
            tauri::image::Image::new_owned(
                include_bytes!("../../icons/tray-icon.png").to_vec(),
                128,
                128,
            )
        }))
        .menu(&menu)
        .show_menu_on_left_click(false)
        .on_menu_event(handle_menu_event)
        .on_tray_icon_event(handle_tray_event)
        .build(app)?;

    Ok(())
}

fn handle_menu_event<R: Runtime>(app: &AppHandle<R>, event: MenuEvent) {
    match event.id().as_ref() {
        "refresh" => {
            let _ = app.emit("menu-refresh-all", ());
        }
        "open" => {
            if let Some(w) = app.get_webview_window("main") {
                let _ = w.show();
                let _ = w.set_focus();
            }
        }
        "quit" => {
            app.exit(0);
        }
        _ => {}
    }
}

fn handle_tray_event<R: Runtime>(tray: &tauri::tray::TrayIcon<R>, event: TrayIconEvent) {
    let app = tray.app_handle().clone();
    if let TrayIconEvent::Click { button, button_state, .. } = event {
        if button_state == MouseButtonState::Up
            && matches!(button, MouseButton::Left)
        {
            if let Some(window) = app.get_webview_window("tray-popover") {
                let _ = window.show();
                let _ = window.set_focus();
            }
        }
    }
}
