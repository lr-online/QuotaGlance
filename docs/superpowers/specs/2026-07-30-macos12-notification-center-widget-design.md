# QuotaGlance macOS 12 Notification Center Widget Design

Status: Approved
Date: 2026-07-30
Branch: `feat/macos12-menu-bar-panel`

## Goal

Give macOS 12 users a configurable Notification Center widget without changing
the shared menu bar popover or weakening the existing macOS 14 desktop Widget
experience.

- Menu bar popover stays identical on macOS 12 and macOS 14.
- macOS 12 edition gains a Notification Center medium widget with account
  configuration.
- macOS 14 edition keeps its current AppIntent desktop widgets and also embeds
  the same Notification Center widget.
- Settings exposes a global default account for Notification Center widgets
  that still use "Use App Default".

## Why A Separate Extension

The existing `QuotaGlanceWidget` target uses `AppIntentConfiguration` and
widget container APIs whose minimum system is macOS 14. Embedding that
extension in the macOS 12 package remains unsupported and unreliable.

Notification Center widgets on macOS 12 can use the older WidgetKit path:
`IntentConfiguration` plus a SiriKit Intent. That path must live in a separate
appex with deployment target macOS 12 so both editions can embed it safely
while the macOS 14 desktop Widget stays untouched.

`QuotaGlanceLegacy` remains the macOS 12 host edition target. The name refers
to the compatibility host, not to a degraded widget product. Both host
editions embed the new Notification Center extension after this change.

## Architecture

### Targets

| Target | Min OS | Role |
|--------|--------|------|
| `QuotaGlance` | 14.0 | Full host; embeds desktop Widget + NC Widget |
| `QuotaGlanceLegacy` | 12.0 | Compatibility host; embeds NC Widget only |
| `QuotaGlanceWidget` | 14.0 | Existing AppIntent desktop widgets (unchanged) |
| `QuotaGlanceNCWidget` | 12.0 | New IntentConfiguration Notification Center widget |

New bundle identifier: `com.liangrui.QuotaGlance.NCWidget`.

### Data flow

1. Host refreshes provider data and writes the versioned App Group snapshot
   (`group.com.liangrui.QuotaGlance`).
2. Host persists preferences through the existing account preferences store.
3. Host calls `WidgetCenter.shared.reloadAllTimelines()` so both extensions
   refresh.
4. `QuotaGlanceNCWidget` reads only the shared snapshot and preferences. It has
   no network access and no Keychain access.
5. Presentation reuses `WidgetPresenter` / `WidgetPresentation` and
   `WidgetSelection`.

### Out of scope for this feature

- Menu bar popover layout or interaction changes
- Changes to `QuotaGlanceWidget` AppIntent configuration, sizes, or desktop
  behavior
- Small or large Notification Center families
- Launch-at-login changes
- Localization
- Collapsing the two edition packages into one

## Configuration Model

### App preference

Add to `AppPreferences`:

```swift
notificationCenterDefaultAccountID: UUID? // nil = All Accounts
```

Rules:

- Persist through the existing `AccountPreferencesStore` path.
- Missing field on decode defaults to `nil`.
- When an account is deleted and it matches the default ID, clear the default
  to `nil` (All Accounts).

### Intent options

The SiriKit Intent account parameter offers:

1. **Use App Default** (initial default for newly added widgets)
2. **All Accounts**
3. Each account from the shared snapshot account list (empty when no snapshot)

Resolution:

| Intent choice | Effective `WidgetSelection` |
|---------------|-----------------------------|
| Use App Default + preference `nil` | `.allAccounts` |
| Use App Default + preference UUID | `.account(uuid)` |
| All Accounts | `.allAccounts` |
| Specific account | `.account(uuid)` |

### Settings UI

Add a **Notification Center Widget** section near Refresh / Notifications:

- Picker: All Accounts plus the current account list
- One-line help: changing this affects widgets still set to Use App Default;
  widgets edited individually in Notification Center are unchanged
- Saving triggers `WidgetCenter.shared.reloadAllTimelines()`

### Interaction

- Tapping the widget opens the existing deep link (`quotaglance://…`) into the
  host app / menu bar surface.
- Manual refresh remains host-only. The widget does not expose a refresh
  control.

## Notification Center Widget Surface

- Family: `.systemMedium` only
- Configuration: `IntentConfiguration`
- Display name / description make clear this is the Notification Center
  QuotaGlance widget and that account selection is available
- Visual states reuse existing Widget presentation semantics:

| State | Presentation |
|-------|--------------|
| No snapshot | No Data |
| Configured account deleted | Account Unavailable |
| Available | Medium layout via shared presentation |
| Stale snapshot | Last snapshot plus freshness |

If Use App Default points at a deleted account, treat rendering as All
Accounts after the host has cleared the preference on delete.

## Packaging, Install, And Verification

### Embedding

- `QuotaGlanceLegacy` embeds `QuotaGlanceNCWidget`.
- `QuotaGlance` embeds `QuotaGlanceNCWidget` and continues to embed
  `QuotaGlanceWidget`.
- Entitlements for the NC appex match the desktop Widget sandbox and App Group
  pattern: sandbox on, same App Group, no network entitlement.

### Script and verifier contract updates

Previously the macOS 12 edition was required to contain **no** `.appex`.
Update that contract:

| Edition | Allowed appexes |
|---------|-----------------|
| legacy (macOS 12) | Only `QuotaGlanceNCWidget.appex` (min 12.0) |
| full (macOS 14) | `QuotaGlanceNCWidget.appex` (min 12.0) and `QuotaGlanceWidget.appex` (min 14.0) |

Update:

- `project.yml`
- `scripts/build-local.sh`
- `scripts/install-local.sh` (register NC bundle with `pluginkit`)
- `scripts/package-dmg.sh`
- `scripts/verify-dmg.sh`
- related script tests
- README and DMG README templates

README wording:

- macOS 12: no desktop widgets; includes configurable Notification Center
  medium widget
- macOS 14: existing desktop widgets plus the same Notification Center widget

Add a focused NC bundle verifier that checks bundle id, WidgetKit extension
point, arm64-only executable, IntentConfiguration path (not AppIntent),
medium-only families, and expected entitlements.

Also update the macOS 12 compatibility design contract language from "no
Widget extension" to "no desktop Widget extension; Notification Center medium
widget is included".

## Testing

### Automated

- Core preference encode/decode for `notificationCenterDefaultAccountID`
- Clearing default account on account deletion
- Intent resolution matrix: Use App Default / All Accounts / specific account
- Presentation coverage continues to rely on `WidgetPresenter`; add NC
  resolution tests where needed
- Build / DMG / local-install script tests assert:
  - both editions contain the NC appex
  - legacy does not contain the desktop Widget appex
  - full contains both appexes with the correct minimum system versions

### Manual verification

- On macOS 12: add the medium widget from Notification Center, change Settings
  default, edit the widget intent, delete the selected account, confirm states
- On macOS 14: confirm desktop AppIntent widgets still behave as before and the
  Notification Center widget works alongside them

## Compatibility Contract Summary

- Shared menu bar popover behavior remains one implementation for both hosts.
- Desktop AppIntent widgets remain macOS 14-only.
- Notification Center IntentConfiguration medium widget ships in both editions.
- Account data, snapshot schema, Keychain storage, refresh intervals, and deep
  links remain shared.
- Users still install only one edition at a time; both keep the same host
  bundle identifier.
