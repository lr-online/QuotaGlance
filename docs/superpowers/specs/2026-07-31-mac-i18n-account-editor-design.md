# Mac Account Editor Polish + Language Settings

**Date:** 2026-07-31  
**Branch:** `feat/mac-i18n-account-editor` (from `main`)

## Goals

1. Beautify the Add/Edit Account sheet: custom labeled rows, short labels, adaptive height (no fixed 340pt whitespace).
2. Add Mac language settings: System / English / 中文, with immediate UI refresh across Settings, menu bar, notifications, and widgets on next timeline refresh.

## Approach

- Persist `preferredLanguage` on `AppPreferences` (default `.system`).
- Resolve to `AppLanguage` (`.english` / `.chinese`) via system preferred languages when set to system.
- Central `L10n` catalog in QuotaGlanceCore for user-visible strings; provider brand names stay English.
- Pass resolved language into presenters (`ErrorPresenter`, `DashboardPresenter`, `WidgetPresenter`, notifications).
- Mirror language into `NCWidgetPreferences` so extensions can localize on next refresh.
- Rebuild `AccountEditorView` as a custom form (not system Form) with fixed-width short labels and content-sized height.

## Non-goals

- HarmonyOS localization
- Translating provider API-sourced metric labels
- String Catalog / `.xcstrings` (macOS 12 + immediate override favor in-app catalog)
