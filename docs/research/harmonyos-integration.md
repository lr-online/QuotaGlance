# HarmonyOS Integration Research

Status: Implemented (see "Implementation status" below)
Date: 2026-07-27

## Implementation status (2026-07-31)

The "full app + ArkTS service widget" recommendation is implemented and
installed on a Huawei Pad Mini. What shipped beyond the minimal loop:

1. **Provider parity with macOS.** All six providers (API Info, DeepSeek,
   Kimi, OpenRouter, MiniMax, BioMap Coding) are ported to ArkTS under
   `Platforms/HarmonyOS/entry/src/main/ets/providers/`, mirroring the Swift
   `UsageProvider` protocol (`fetch` / `detect` / `fetchWithProfile`),
   `ProviderProfile` (region + credentialKind), the `UsageSnapshot` model
   (decimal-string money), and the shared error taxonomy. Region detection
   and multi-step flows (OpenRouter management keys, BioMap `/v1/models`
   fallback) behave as on macOS.
2. **Drift prevention via shared contract fixtures** (architecture decision
   3 below, now realized): `Contracts/Providers/<provider>/<case>-{response,expected}.json`
   is the single source of truth. Swift asserts against them in
   `Shared/SwiftCore/Tests/QuotaGlanceCoreTests/ContractTests.swift`; HarmonyOS asserts
   against the same files synced into ohosTest rawfile by
   `scripts/sync-contracts-to-harmonyos.sh` (suite:
   `Platforms/HarmonyOS/entry/src/ohosTest/ets/test/Contract.test.ets`). Schema and
   workflow: `Contracts/README.md`. Adding or changing a provider requires
   updating fixtures + both test suites, so parsing drift fails CI on both
   platforms.
3. **Credential storage (section 6 decision, applied).** API keys live in
   Asset Store Kit under per-account aliases (`quotaglance_key_<accountId>`)
   with `DEVICE_FIRST_UNLOCKED` accessibility; the pre-multi-account single
   alias is migrated once into a DeepSeek account. Asset Store remains the
   correct store for credential blobs; HUKS is for cryptographic keys the
   app uses for signing/encryption, which this app does not need. Future
   hardening option: gate key reads behind user authentication
   (`AUTH_TYPE` + userAuth) if device-sharing becomes a concern.
4. **Brand alignment.** The macOS icon design (navy gradient, teal progress
   ring, usage-chart polyline) is rendered into the HarmonyOS layered icon
   and start window by `scripts/generate-harmonyos-icon.swift`; the app UI
   uses the same navy/teal palette (`entry/.../element/color.json`).
5. **Configuration flow.** Multi-account management (add via provider
   picker + live key validation through `provider.detect`, enable toggle,
   delete with cascade) in `pages/AccountsPage.ets` /
   `pages/AccountEditorPage.ets`; account metadata in preferences
   (`storage/AccountStore.ets`), snapshots per account
   (`storage/SnapshotStore.ets`), orchestration in
   `services/AccountService.ets`. Account detail page
   (`pages/AccountDetailPage.ets`) surfaces the full snapshot — balances,
   spending limit, quota windows, today counters, a last-7-days chart
   matching the macOS menu-bar `makeDays` semantics, and model usage.
6. **In-app screensaver mode (section 8, implemented).**
   `pages/ScreensaverPage.ets`: foreground keep-screen-on fullscreen with
   hidden system bars, pure-black background, a large clock plus one
   primary-metric row per enabled account, 5-minute polling, and a
   60-second pixel drift against OLED burn-in. Tap anywhere to exit; window
   state (brightness via the `-1` follow-system sentinel, system bars,
   fullscreen, keep-screen-on) is restored on exit and in
   `aboutToDisappear`. An account detail screen can also be the source, in
   which case the full per-account detail renders in a dim palette and only
   that account is polled.
   **Charging-aware brightness (2026-07-31).** The original fixed 0.08
   window brightness proved effectively invisible. The policy is now:
   default visible-dim 0.25, 0.30 while charging, 0.18 on battery. The
   charging state is read from `batteryInfo.chargingStatus`
   (`@kit.BasicServicesKit`, ENABLE/FULL = charging; no permission needed)
   and re-evaluated on every 60-second drift tick; `setWindowBrightness` is
   only called when the level actually changes, and batteryInfo read
   failures fall back to 0.25. Content opacities were raised to match
   (clock at full strength, account rows at 0.85/0.9, dim detail palette
   brightened to #C9D1DC text / ~0.9-alpha teal / #0D1119 cards).
   **Standby screensaver card (section 1, evaluated 2026-07-31).** The
   SDK's modulecheck schema (`toolchains/modulecheck/forms.json`) documents
   a compile-safe `standby` object in form_config (`isSupported`,
   `isAdapted`, `isPrivacySensitive`), so the existing 2×2-capable card now
   declares `isSupported: true` with `isAdapted: false` (no standby-specific
   UX pass yet) and `isPrivacySensitive: true` (balances on a lock screen).
   Actually surfacing there still requires the AppGallery capability
   application, API 23+, and a supported phone model — the declaration is
   inert until then, and our target Pad Mini (tablet) is outside the
   supported device set anyway.

Still open from the research below: the AppGallery capability application
for the standby screensaver card (gated, API 23+ phones), charging-triggered
screensaver entry, and anything requiring AppGallery review.



Scope: HarmonyOS NEXT (HarmonyOS 5.x, ArkTS/ArkUI ecosystem) on phones,
tablets, and HarmonyOS PCs. All claims are based on Huawei's official
developer documentation (developer.huawei.com). Points without official
backing are explicitly marked "No official basis found."

## Decision

For QuotaGlance's shape — a read-only dashboard that polls HTTPS endpoints
with API keys and renders balances — the lightest HarmonyOS entry points,
ranked:

1. **Full app + ArkTS service widget (FormExtensionAbility).** One HTTP
   client, one card, 30-minute periodic refresh. This maps almost one-to-one
   onto the macOS widget architecture.
2. **Atomic service (元服务) with the same card architecture.** Install-free
   and smaller, but still requires AppGallery review, and background-task
   support is undocumented. Choose only if install-free entry matters.
3. **Backend-polled, push-driven card refresh (卡片代理刷新).** Only worth it
   if sub-30-minute freshness is required or if roadmap item 8 decides on a
   shared backend anyway.

**Always-on display / screensaver answer: not feasible as a third-party app
surface.** Phone/tablet AOD is theme content, not an app API; no official
API exists for an app to render custom data (e.g. a balance) on the AOD
screen. The only quasi-screensaver channel is the standby screensaver card
(待机屏保卡片, API 23+, landscape-charging lock screen, 2×2 only, selected
phone models, gated by an AppGallery capability application). No official
HarmonyOS PC screensaver API was found.

An **in-app custom screensaver mode** (foreground fullscreen keep-screen-on
dashboard, the pre-StandBy clock-app pattern) is feasible with official APIs
and combines naturally with option 1: the same app that ships the service
widget adds a fullscreen mode using `setWindowKeepScreenOn`, foreground
polling at any interval, and `batteryInfo` charging detection. It is a
companion surface, not a substitute — it only lives while the app stays in
the foreground, and Huawei reserves keep-screen-on for justified scenarios,
so the system may still override it (see section 8).

Live View (实况窗) is unsuitable: it is a session-based, scenario-allowlisted,
approval-gated feature with an 8-hour maximum lifespan, not a persistent
dashboard.

No HarmonyOS mechanism can poll HTTPS every 5–30 minutes in the background.
The practical floor is the card's 30-minute periodic refresh; WorkScheduler's
floor is 2 hours even for active apps.

## Architecture decisions (2026-07-27)

Settled in a design review; these close roadmap item 8's open questions for
HarmonyOS only (Android and Windows remain unevaluated):

1. **UI: per-platform, no shared UI layer.** SwiftUI/AppKit/WidgetKit on
   macOS, ArkUI/ArkTS on HarmonyOS. Cross-platform UI frameworks (Flutter
   with the OHOS fork) were rejected: the product's value is its native
   surfaces (menu bar, WidgetKit, service widget), which cross-platform
   frameworks serve as second-class citizens.
2. **Architecture: client-only, no backend.** API keys never leave the
   device (macOS Keychain / HarmonyOS Asset Store Kit). A shared backend was
   rejected for a personal tool: it changes the key-custody model, adds
   operations cost, and buys nothing the current usage needs. Revisit only
   if platform count exceeds two or the 30-minute card refresh floor proves
   painful in real use.
3. **Core logic: per-platform implementations with shared contract
   fixtures.** A unified Go/Rust native core was rejected. Go has no
   official OHOS target (community forks and the `GOOS=android` toolchain
   trick only); Rust does (Tier 2 `aarch64-unknown-linux-ohos`), but the
   platform-independent core is only ~a third of `QuotaGlanceCore`, and FFI
   would mean three codebases (Rust core + UniFFI/Swift bindings +
   napi-rs/ArkTS bindings). Instead, provider response fixtures and parsing
   expectations become shared JSON contract files that both platforms run in
   CI, so logic drift fails the build. Re-evaluate a shared native core when
   a third platform arrives, provider count doubles, or drift bugs actually
   appear.
4. **Positioning: personal use first, minimal closed loop.** First
   HarmonyOS version = ArkTS app + key entry (Asset Store) + service widget
   with 30-minute polling, sideloaded via DevEco Studio debug signing — no
   AppGallery review, no Live View. Only the providers the owner actually
   holds keys for get implemented (no way to verify parsing otherwise). The
   in-app screensaver mode is phase two, after the basic loop is proven on
   a real device.

## 1. Always-On Display / Screensaver

Status: Evaluated. AOD as an app surface is not feasible; standby screensaver
cards are a limited alternative.

- Phone/tablet AOD (息屏显示/熄屏显示) is produced through the theme
  ecosystem: AOD themes are image/animation packages designed in Theme
  Studio and distributed in the Themes app. Individual and enterprise
  developers can publish AOD *themes*, but these are static art, not
  programmable surfaces fed by live app data.
- No official basis found for any public API that lets a third-party app
  render custom content or push real-time data (such as a balance number)
  onto the AOD screen.
- Notifications surface only as icons on the AOD screen ("通知图标：以图标
  形式显示在状态栏、AOD 界面"); an app cannot place values there.
- Standby screensaver cards (待机屏保卡片) are the closest official channel:
  - From API version 23, Form Kit can show a 2×2 card on the standby
    screensaver interface (the landscape-charging lock screen).
  - Only 2×2 size, only some phone models; privacy-sensitive data is
    officially discouraged on it.
  - Requires an "open capability" application in AppGallery Connect and
    manual signing; it shares the normal FormExtensionAbility data pipeline
    with desktop cards.
  - It is a docked-charging surface, not the always-on lock screen.
- HarmonyOS PC (2in1) screensaver API: No official basis found. No
  screensaver development documentation exists for HarmonyOS computers.

Official sources:

- https://developer.huawei.com/consumer/cn/doc/HarmonyOS-Guides/arkui-ui-standby-form-development
- https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/arkts-ui-widget-configuration (standby tag)
- https://developer.huawei.com/consumer/cn/doc/best-practices/bpta-always-on-market-watch
- https://developer.huawei.com/consumer/cn/doc/aod-test-0000001056821215 (theme-center AOD review rules)
- https://developer.huawei.com/consumer/cn/doc/learn-guidance-0000001075527080 (AOD distributed as themes)
- https://developer.huawei.com/consumer/cn/doc/design-guides/system-features-notification-0000001793074217

## 2. Atomic Service (元服务)

Status: Evaluated. Technically feasible, distribution-gated.

- Atomic services are install-free packages presented mainly as service
  widgets; `bundleType` must be `atomicService` and every HAP must be
  installation-free.
- Package limits: total APP package ≤ 10 MB; each individual package
  (including its dependency HSPs) ≤ 2 MB. A JSON-rendering dashboard fits
  comfortably.
- Atomic services may only use the "atomic service API set"; native C/C++
  (SO files) are not allowed. Within that set:
  - `@kit.NetworkKit` HTTP (`http.createHttp`) is atomic-service-compatible
    from API 11, so HTTPS polling works.
  - `FormExtensionAbility` is atomic-service-compatible from API 11, so
    cards work.
- Whether atomic services may use background-task APIs (transient,
  long-running, WorkScheduler): No official basis found. The background-task
  guides consulted carry no atomic-service annotation, while Form Kit and
  Network Kit explicitly do. Assume the card refresh model, not background
  polling.
- Distribution requires AppGallery Connect review and listing, same as
  apps; there is no private atomic-service channel for end users. During
  development an atomic service can be debug-run on the developer's own
  device.
- Account types include individual developers with real-name verification;
  nothing in the publish flow excludes individuals.

Official sources:

- https://developer.huawei.com/consumer/cn/doc/app/agc-help-release-atomic-prepare-0000002327610825
- https://developer.huawei.com/consumer/cn/doc/harmonyos-references-V5/js-apis-http-V5
- https://developer.huawei.com/consumer/cn/doc/harmonyos-references/js-apis-app-form-formextensionability
- https://developer.huawei.com/consumer/cn/doc/service/harmonyos_agreement-0000001238515921
- https://developer.huawei.com/consumer/cn/doc/start/registration-and-verification-0000001053628148

## 3. Service Widgets (FormExtensionAbility)

Status: Evaluated. This is the primary surface for QuotaGlance.

- Periodic refresh granularity: `updateDuration` is measured in units of
  30 minutes (N = 1 → every 30 minutes). `scheduledUpdateTime` refreshes at
  one fixed time of day; `multiScheduledUpdateTime` (API 18+) allows up to
  24 fixed times per day. QuotaGlance's 1–60 minute interval maps onto
  30-minute multiples; anything below 30 minutes is not achievable via the
  card timer.
- `dataProxyEnabled` (API 12+) enables push-driven proxy refresh (卡片代理
  刷新): a backend pushes updates through the system instead of the device
  polling. Enabling it disables timer and next-refresh updates (fixed-time
  updates still work).
- `conditionUpdate: network` (effective from API 26.0.0) lets the system
  trigger refresh on network availability.
- A refresh tick invokes `FormExtensionAbility.onUpdateForm`; the provider
  then fetches data and calls `formProvider.updateForm`. The
  FormExtensionAbility is reclaimed after 10 seconds of inactivity, so each
  refresh must be one quick request — fine for QuotaGlance's single GET per
  provider.
- `backgroundTaskManager` is explicitly prohibited inside
  FormExtensionAbility, so cards cannot escalate themselves into background
  tasks.
- Card color modes (API 15+): `fullColor` for desktop; `singleColor` can
  also be added to the lock screen; `autoColor` works on both. Lock-screen
  cards exist but are a user-managed surface, not AOD.
- `supportDeviceTypes` defaults (API 22+) already include phone, tablet,
  and `2in1` (HarmonyOS PC).

Official sources:

- https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/arkts-ui-widget-configuration
- https://developer.huawei.com/consumer/cn/doc/harmonyos-references/js-apis-app-form-formextensionability
- https://developer.huawei.com/consumer/cn/doc/best-practices/bpta-card-update-and-data-interaction
- https://developer.huawei.com/consumer/cn/doc/harmonyos-guides-V5/push-form-update-V5 (proxy refresh via `dataProxyEnabled`)

## 4. Live View (实况窗)

Status: Evaluated. Unsuitable.

- Live View is restricted to an allowlist of session scenarios: taxi,
  delivery, flight, train, queue, meal pickup, sports score, rental, timer,
  workout, navigation, check-in, express, file-progress. Each scenario
  requires a per-scenario entitlement application in AppGallery Connect.
- The application form is only available to apps that are already listed
  and have ≥ 1000 monthly active users — a hard gate for a personal
  project.
- Maximum lifespan is `aliveTime` ≤ 28800 s (8 hours); Live View models a
  finite service session with a start and an end, not an ambient indicator.
- There is no scenario category for "recurring balance/quota display", and
  using it as a persistent dashboard would violate the design review the
  entitlement process enforces.

Official sources:

- https://developer.huawei.com/consumer/cn/doc/harmonyos-references/liveview-liveviewmanager
- https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/liveview-formal-authority

## 5. Background Tasks

Status: Evaluated. None matches "poll HTTPS every 5–30 minutes".

- Background work is only possible inside the four sanctioned types;
  otherwise the process is suspended or killed.
- Transient task (短时任务): max 3 concurrent, single run ≤ 3 minutes,
  default daily quota 10 minutes (1 minute on low battery). For
  finishing in-flight work, not periodic polling.
- Long-running task (长时任务): for continuous, user-perceivable scenarios
  (music playback, navigation, device connection). A silent quota poller
  does not qualify.
- WorkScheduler (延迟任务): condition-triggered and system-scheduled.
  Frequency is tiered by app activity group — minimum interval 2 hours
  (active), 4 hours (frequent), 24 hours (common), 48 hours (rarely used),
  forbidden entirely for restricted/never-used groups. Max 10 works per
  app; each callback ≤ 2 minutes. Even the best case (2 hours) misses a
  5–30 minute target.
- Agent-powered reminders (代理提醒): countdown, calendar, and alarm
  reminders only — notifications, not data refresh.
- Conclusion: on-device periodic refresh below 30 minutes is only possible
  while the app is in the foreground. The realistic options are the card's
  30-minute timer refresh, WorkScheduler at ≥ 2 hours, or server-side
  polling with push-driven proxy refresh.

Official sources:

- https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/background-task-overview
- https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/transient-task
- https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/work-scheduler

## 6. Secure Storage

Status: Evaluated. A Keychain equivalent exists and is open to normal
third-party apps.

- Asset Store Kit (`@kit.AssetStoreKit`) stores short sensitive values —
  passwords, tokens, credentials — with lock-screen-state access control
  (powered-on / first-unlock / unlocked) and optional user authentication
  (PIN, face, fingerprint). ArkTS API from API 11. This is the direct
  counterpart of macOS Keychain for API keys.
- Optional persistence across uninstall (`IS_PERSISTENT`) requires the
  `ohos.permission.STORE_PERSISTENT_DATA` permission.
- Universal Keystore Kit (HUKS) provides key generation, import, and
  cryptographic use for apps that need keys rather than stored secrets.

Official sources:

- https://developer.huawei.com/consumer/cn/doc/harmonyos-references-V5/js-apis-asset-V5
- https://developer.huawei.com/consumer/cn/doc/harmonyos-guides-V5/huks-overview-V5

## 7. Development and Distribution Thresholds

Status: Evaluated.

- Stack: DevEco Studio + ArkTS/ArkUI. No official basis found for reusing
  Swift code; the documented application framework is ArkTS/ArkUI (with
  C/C++ native only for full apps, not atomic services). QuotaGlanceCore's
  logic would need an ArkTS rewrite; only the provider JSON contracts
  documented in `docs/research/provider-capabilities.md` carry over.
- Individual developers can register with real-name verification; a company
  account is not required.
- Signing: DevEco Studio automated signing covers on-device debugging, with
  the developer's devices written into the debug profile. Release builds
  must be manually signed, and store listing goes through AppGallery
  Connect review.
- Sideloading: No official basis found for installing release apps on
  arbitrary phones outside AppGallery. The documented personal-use path is
  debug-signed installation from DevEco Studio onto registered devices.
- Gated capabilities used elsewhere in this document (standby screensaver
  card, Live View, some ACL permissions) require AppGallery capability
  applications on top of normal signing.

Official sources:

- https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/ide-signing
- https://developer.huawei.com/consumer/cn/doc/start/registration-and-verification-0000001053628148
- https://developer.huawei.com/consumer/cn/doc/start/dbiae-0000001336403980

## 8. In-app custom screensaver mode

Status: Evaluated. Feasible with official APIs, as a foreground-only
companion surface — the pre-StandBy clock-app pattern (fullscreen always-on
dashboard inside the app).

Implementation points, all confirmed against official documentation:

- Keep screen on: `window.setWindowKeepScreenOn(isKeepScreenOn)` from
  `@kit.ArkUI`, called on the app's own window. No permission declaration is
  documented; the official best practices use it directly. It overrides the
  system sleep timeout while the app's window is in the foreground.
  - Official constraint: Huawei documents it for justified scenarios
    (navigation, video playback, drawing, gaming) and warns that "系统检测到
    非规范使用该接口时，可能会恢复自动熄屏功能" — when the system detects
    non-compliant use (e.g. no-interaction screens), it may restore
    automatic screen-off. A passive dashboard is in this gray zone, so the
    mode must tolerate being overridden.
- Fullscreen immersion: `setWindowLayoutFullScreen` plus
  `setWindowSystemBarEnable` (hide status bar and navigation bar) per the
  official immersive-window guide. Per-window brightness
  (`setWindowBrightness`) can dim the dashboard and restores the system
  brightness on exit.
- Foreground polling freedom: suspension and resource cutoff (timers,
  network) apply only after the app goes to background (home, lock screen,
  app switch). A foreground app keeps timers and network, so `setInterval`-
  style polling with `@kit.NetworkKit` at any interval (e.g. 5 minutes) is
  possible while the mode is on screen. No official basis found for any
  "long foreground inactivity" suspension mechanism.
- Charging detection: `batteryInfo` from `@kit.BasicServicesKit` exposes
  `chargingStatus` (NONE/ENABLE/DISABLE/FULL), `pluggedType`
  (AC/USB/WIRELESS), and `batterySOC`, plus the
  `COMMON_EVENT_BATTERY_CHANGED` event keys — enough for "enter screensaver
  mode on charge, exit on unplug". No permission is documented for these
  read APIs; they are also atomic-service-compatible from API 12.
- Relationship to the system standby screensaver card (section 1): the two
  are complementary, not conflicting. The in-app mode works on any device
  and orientation without approval, but only while foreground; the standby
  card is system-managed and survives the app being closed, but is gated
  (API 23+, selected phones, capability application). Whichever surface is
  active excludes the other: while keep-screen-on holds, the device never
  sleeps so the system standby UI never appears; once the user locks the
  device or the system overrides keep-screen-on, the app is suspended and
  system surfaces (lock screen, standby, AOD) take over.
- OLED and power: no app-side official burn-in guideline was found.
  Indirect official references exist for the system's own always-on
  surfaces: AOD themes must keep non-black pixels under 15% of the screen,
  and the standby screensaver interface is dark-mode-only by design.
  Following the same pattern (dark background, dimmed brightness, periodic
  content drift) is prudent design, not an official requirement.
- Ecosystem precedent (non-official): third-party flip-clock apps
  advertising HarmonyOS NEXT support with an always-on screensaver mode
  exist on consumer download channels, indicating store acceptance of the
  pattern; this is an observation, not an official statement.

Official sources:

- https://developer.huawei.com/consumer/cn/doc/best-practices/bpta-page-brightness-settings
- https://developer.huawei.com/consumer/cn/doc/architecture-guides/traffic-v1_1-ts_47-0000002383153938 (usage constraints of `setWindowKeepScreenOn`)
- https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/immersive-window-feature
- https://developer.huawei.com/consumer/cn/doc/harmonyos-references/js-apis-battery-info
- https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/background-task-overview (suspension applies to backgrounded apps)
- https://developer.huawei.com/consumer/cn/doc/aod-test-0000001056821215 (≤ 15% non-black pixels rule for AOD themes)

## Recommendation for QuotaGlance

Ranked by integration weight for a periodic read-only dashboard:

1. **Full app + ArkTS service widget.** One `EntryAbility` for setup
   (provider picker, key entry into Asset Store Kit) plus one
   FormExtensionAbility that polls providers with `@kit.NetworkKit` on the
   30-minute card timer and keeps the last snapshot with a stale marker on
   failure — the same contract as the macOS widget. Debug-signed
   self-installation covers personal use before any store decision.
2. **Atomic service with the same card.** Marginally lighter for end users
   (install-free) but capped at 2 MB per package, restricted to the atomic
   API set, with undocumented background-task support — and it still
   requires AppGallery review to reach users. Not lighter overall for this
   project.
3. **Backend-polled proxy-refresh card.** Move provider polling to a shared
   backend and push snapshots to the card (`dataProxyEnabled`). This is the
   only way to beat the 30-minute floor and to stop shipping API keys to
   devices, and it aligns with the open client-vs-backend question in
   roadmap item 8. It is also the heaviest option and should wait for that
   decision.

Optional companion to option 1: an in-app custom screensaver mode (section
8) — fullscreen, dimmed, keep-screen-on dashboard with free-interval
foreground polling and charging-triggered entry. It costs little inside the
same app, but it only lives in the foreground and Huawei may override
non-compliant keep-screen-on use, so it is a bonus surface, never the core
refresh path.

Explicitly rejected:

- AOD / screensaver as the main surface (see section 1): no third-party app
  API; the standby screensaver card is an optional extra for API 23+ phones
  after the main app exists, not a substitute.
- Live View: scenario allowlist, entitlement review, ≥ 1000-MAU gate,
  8-hour cap.
- WorkScheduler/transient/long-running tasks for 5–30 minute polling:
  platform floors of 2 hours, 10 minutes/day, and user-perceivable
  scenarios respectively.
