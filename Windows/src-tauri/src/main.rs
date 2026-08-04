// Windows portable client entry point.
//
// This file is intentionally minimal. Real wiring (tray icon, single-instance
// lock, deep-link handler, command registry, refresh coordinator, DPAPI
// credential vault) lands in subsequent milestones; the scaffold only needs to
// prove the binary starts Tauri 2 and opens a host process.
//
// Keep this file free of behaviour that belongs in lib.rs (test harness needs
// to instantiate lib::run() without spawning a GUI), and free of
// platform-specific imports (DPAPI lives in src-tauri/src/storage/credential_vault.rs,
// not here).

#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

fn main() {
    quotaglance_tauri_lib::run();
}
