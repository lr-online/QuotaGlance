# QuotaGlance Phase-One Design

Status: Approved for written-spec review
Date: 2026-07-22

## Objective

Build a native macOS menu bar app and WidgetKit extension that let one person
monitor two to five API Info credentials on their local Mac. The finished app
must be installable and usable locally without App Store distribution. The user
must be able to add a QuotaGlance widget from the macOS widget gallery and see
live API Info data that the host app has refreshed.

## Phase-One Scope

Phase one includes:

- API Info as the only active data provider.
- Two to five independently named API Info credentials.
- Aggregate and per-account balances and usage.
- A native menu bar panel and Settings window.
- Small, medium, and large desktop widget families.
- Configurable refresh intervals of 1, 5, 15, 30, or 60 minutes, defaulting to
  5 minutes.
- Manual refresh from the menu bar panel.
- Per-account low-balance notification thresholds.
- Optional launch at login.
- Local development signing and installation into `~/Applications`.

Phase one does not include:

- App Store distribution, notarization, or a public installer.
- OpenRouter, DeepSeek, Kimi, MiniMax, or a provider selection interface.
- Currency conversion.
- Cloud sync, shared accounts, or remote administration.
- A runtime third-party plugin system.
- Direct network access or Keychain access from the widget extension.

Research for deferred providers is recorded in
`docs/research/provider-capabilities.md`.

## Platform And Targets

- Minimum deployment target: macOS 14.
- Primary development and validation machine: Apple Silicon, macOS 26.5.
- Host target: SwiftUI macOS application using `MenuBarExtra` with window style.
- Widget target: WidgetKit extension using App Intent configuration.
- Shared code target: domain models, snapshot models, formatting, and widget
  presentation logic used by both bundles.
- Test target: unit and integration tests with no real credentials.

Initial local identifiers are:

- host bundle: `com.liangrui.QuotaGlance`;
- widget bundle: `com.liangrui.QuotaGlance.Widget`;
- App Group: `group.com.liangrui.QuotaGlance`;
- deep-link scheme: `quotaglance`;
- shared snapshot file: `quota-snapshot-v1.json`.

The host is an accessory-style menu bar app and does not require a permanent
Dock icon. Settings and account management open in ordinary macOS windows.

## User Experience

### First Launch

When no account exists, the menu bar panel shows an empty state with an Add
Account command. Adding an account asks for:

- display name;
- API key;
- optional low-balance threshold in USD;
- enabled or disabled state.

The API key field is secure text. Saving validates the key with API Info before
creating the account. A validation failure leaves the entered data available
for correction and does not create a misleading healthy account.

### Menu Bar Panel

The selected balance-led dashboard contains:

- account selector, defaulting to All Accounts;
- available balance as the visual anchor;
- today's actual spend and request count;
- seven-day aggregate usage chart when daily data exists;
- accounts needing attention;
- last successful refresh time and stale/partial state;
- manual refresh command;
- Settings command.

All Accounts sums enabled accounts. Selecting one account replaces the summary
with its individual quota, usage, daily series, and model statistics.

### Settings

Settings contains:

- Accounts: add, rename, reorder, enable, disable, replace key, set threshold,
  and delete.
- Refresh: interval selector and launch-at-login toggle.
- General: notification permission status and a brief data freshness status.

Deleting an account requires confirmation and removes its Keychain item,
metadata, alert state, and cached snapshot.

### Widgets

Each widget can be configured for All Accounts or one account:

- Small: remaining balance, today's spend, and freshness status.
- Medium: remaining balance, today's spend, request count, and seven-day trend.
- Large: aggregate metrics, trend, and up to five account rows with threshold
  state.

When an account-specific configuration refers to a deleted account, the widget
shows a clear unavailable state and invites the user to edit the widget.

The widget reads only the latest shared snapshot. Tapping it opens the host app
for the selected account. Phase one does not place a network-backed refresh
button inside the widget; manual network refresh remains in the host app.

## Visual Direction

The UI uses native macOS materials, semantic typography, and system colors.
Available balance is the only large numeric element. Color communicates state:

- green for healthy and fresh;
- amber for below-threshold or partially stale;
- red for invalid credentials or unrecoverable provider errors;
- system neutrals for all ordinary structure.

Charts remain low contrast and emphasize the current day. The interface follows
light mode, dark mode, increased contrast, and reduced-transparency settings.

## Architecture

### Host Application

The host owns all privileged and active behavior:

- `AccountStore`: account metadata and ordering.
- `KeychainStore`: create, read, replace, and delete API keys.
- `UsageProvider`: narrow source-level provider contract.
- `APIInfoProvider`: phase-one provider implementation.
- `RefreshCoordinator`: startup refresh, scheduled refresh, manual refresh, and
  overlapping-refresh suppression.
- `SnapshotBuilder`: per-account and aggregate normalized snapshots.
- `SharedSnapshotStore`: atomic App Group file writes.
- `AlertEvaluator`: low-balance episode tracking.
- `NotificationService`: local notification authorization and delivery.
- `LaunchAtLoginService`: `SMAppService` integration.

The `UsageProvider` boundary exists to prevent vendor JSON from leaking into the
refresh and UI layers. Phase one registers only `APIInfoProvider`; it does not
build unused capability abstractions or inactive adapters.

### Widget Extension

The widget extension owns only:

- App Intent account selection based on snapshot account metadata;
- shared snapshot reads;
- placeholder, snapshot, and timeline entry construction;
- small, medium, and large SwiftUI widget views;
- deep links back to the host.

It does not read API keys, call API Info, evaluate notifications, or mutate
account settings.

### Shared Container

The host and widget use an App Group container. The host writes one versioned
Codable snapshot file with `Data.write(options: .atomic)`. The widget tolerates
missing, older, and temporarily unreadable snapshots.

The shared snapshot includes only:

- account UUID and display name;
- normalized balances and usage;
- seven-day daily values;
- account health and stale state;
- captured and last-success timestamps;
- aggregate data;
- schema version.

It never includes API keys, raw authorization headers, or full request/response
logs.

## Data Model

### Account Metadata

An account contains:

- stable local UUID;
- display name;
- provider identifier (`api-info` in phase one);
- enabled state;
- sort order;
- optional USD threshold represented as `Decimal`;
- alert-episode state;
- creation and modification timestamps.

The Keychain generic-password item uses the account UUID as its account name and
the service identifier `com.liangrui.QuotaGlance.api-info`. Non-secret account
metadata and app preferences use a versioned Codable payload in the host app's
standard preferences container. Only the normalized widget snapshot is copied
to the App Group.

### Normalized Snapshot

Money is represented by `Decimal` plus the provider's currency code. Token and
request counts use 64-bit integers. Optional provider fields remain optional;
absence is never normalized to zero.

Per-account snapshots contain:

- authoritative remaining amount;
- quota limit and used amount when supplied;
- today's actual cost, requests, and token counts;
- total actual cost, requests, and token counts;
- daily usage entries;
- model statistics;
- provider status and freshness timestamps.

Aggregate snapshots sum only enabled accounts with compatible USD data. Daily
series are grouped by provider date. A failed account keeps its last successful
values but makes the aggregate explicitly partial.

## API Info Contract

Request:

```http
GET https://www.api-info.net/v1/usage
Authorization: Bearer <API key>
Accept: application/json
```

Phase one consumes:

- top-level `remaining`, `unit`, `status`, and `isValid`;
- `quota.limit`, `quota.used`, and `quota.remaining`;
- `usage.today` and `usage.total`;
- `daily_usage`;
- `model_stats`.

The top-level `remaining` value is authoritative. QuotaGlance does not derive
remaining balance by subtracting usage fields because provider totals can differ
slightly. Spend displays use `actual_cost` when present. Decoding tolerates
additional fields and missing optional statistics.

## Refresh And Data Flow

1. The app performs an immediate refresh after launch when enabled accounts
   exist.
2. `RefreshCoordinator` reads each enabled key from Keychain.
3. `APIInfoProvider` requests enabled accounts concurrently, with a maximum of
   five requests and a 15-second timeout per request.
4. Each result independently updates or preserves the account's last successful
   snapshot.
5. `SnapshotBuilder` creates account and aggregate views.
6. The host writes the versioned snapshot atomically to the App Group.
7. `AlertEvaluator` processes fresh successful balances.
8. The host calls `WidgetCenter.reloadAllTimelines()`.
9. The next scheduled refresh uses the selected interval.

Scheduled and manual refreshes coalesce: only one refresh operation can run at a
time. A manual refresh requested during an active refresh reuses the active
operation instead of starting duplicate requests. Phase one waits for the next
normal interval after a failure rather than implementing aggressive retries.

Widget timelines request a conservative future reload while relying primarily
on host-triggered reload requests. WidgetKit scheduling remains system-managed,
so the UI always exposes the last-success timestamp instead of promising exact
real-time widget refresh.

## Notifications

Each account can enable one USD low-balance threshold. Notifications are local
and account-specific.

An alert fires once when a fresh successful balance is at or below the threshold
and the current below-threshold episode has not already been announced. The
episode resets only after a later fresh balance rises above the threshold.
Failures and stale cached values never create new alerts.

Notification authorization is requested when the user first enables a
threshold, not at app launch. Denied authorization is shown in Settings without
blocking balance monitoring.

## Error Handling

- Missing Keychain item: mark the account as requiring key repair.
- HTTP 401/403 or `isValid == false`: mark credentials invalid and retain the
  last successful values as stale.
- HTTP 429: show rate limited and retain stale values.
- Network timeout/offline: show unavailable and retain stale values.
- Decode/schema failure: show provider response error and retain stale values.
- One-account failure: refresh other accounts and mark aggregate data partial.
- No successful snapshot yet: show an account-specific empty/error state rather
  than fabricated zero balances.
- Shared snapshot read failure: widget shows its last timeline entry when
  available, otherwise a neutral unavailable state.

User-facing errors are concise and actionable. Diagnostic logging includes
account UUID, status category, and timing, but never credentials, authorization
headers, or raw provider bodies.

## Security And Privacy

- API keys are stored only in macOS Keychain.
- `.env` files and `.superpowers/` content remain ignored by Git.
- The widget extension has no key access and no network role.
- The app uses App Sandbox outgoing-network entitlement and the minimum required
  App Group and Keychain capabilities.
- No analytics, crash upload, remote logging, or cloud sync is included.
- Tests and fixtures contain sanitized API responses only.
- Repository and built-product checks must confirm that known key values are not
  embedded.

## Local Build And Installation

The project uses an Xcode app target, widget extension target, shared code, and
tests. A complete Xcode installation is required; Command Line Tools alone
cannot build the app extension.

Local delivery uses Xcode development signing as the primary path. Sign to Run
Locally is an acceptable fallback only if the App Group entitlement is verified
to work for both bundles on the target Mac. Delivery does not require App Store
submission, Developer ID distribution, notarization, or a package installer.

An installation script will:

1. build the selected local configuration;
2. replace only `~/Applications/QuotaGlance.app`;
3. launch the installed host app once;
4. print concise instructions for adding QuotaGlance from the widget gallery.

The script must validate its source and destination paths before replacing the
existing app. The widget extension remains embedded inside the host app.

## Testing Strategy

Automated tests cover:

- API response decoding with complete, optional-field, and malformed fixtures;
- authoritative `remaining` behavior when accounting fields differ;
- two-to-five-account aggregation and date grouping;
- partial success and stale-value preservation;
- refresh coalescing and timeout mapping;
- Keychain store behavior through an injected test implementation;
- alert episode transitions;
- versioned snapshot encoding/decoding;
- widget entry construction for aggregate, account, stale, deleted, and empty
  configurations;
- deep-link routing.

Integration tests use an injected `URLProtocol` and never call the real API.

Manual verification covers:

- first-run account creation with a real API Info key;
- two-account aggregate and account switching;
- selectable refresh intervals and manual refresh;
- local notification delivery;
- light and dark appearance;
- small, medium, and large widget rendering;
- host relaunch, login-item behavior, and stale offline behavior.

## Acceptance Criteria

Phase one is complete only when all of the following are demonstrated on the
local Mac:

1. A development-signed `QuotaGlance.app` builds successfully.
2. The app is installed at `~/Applications/QuotaGlance.app` and launches.
3. A user can add at least two API Info keys without secrets entering project
   files or logs.
4. The menu bar panel shows live per-account and aggregate remaining balance,
   today's usage, requests, and seven-day trend.
5. Refresh defaults to five minutes, all specified intervals are selectable,
   and manual refresh works.
6. A configured threshold produces at most one notification per low-balance
   episode.
7. QuotaGlance appears in the macOS widget gallery after host installation and
   launch.
8. Small, medium, and large widgets can be added to the desktop and show the
   latest shared aggregate or selected-account snapshot.
9. A failed key or offline request preserves old values and clearly marks them
   stale or partial.
10. Automated tests pass, and repository/built-product secret scans find no API
    key material.
