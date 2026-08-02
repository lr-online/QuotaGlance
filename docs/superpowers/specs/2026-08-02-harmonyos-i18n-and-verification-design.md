# HarmonyOS i18n + Verification Loop Design

**Date:** 2026-08-02  
**Status:** Approved for planning  
**Scope:** Two independent deliverables in one track

## Goals

1. **HarmonyOS full i18n** — Support three language modes matching macOS:
   - Follow System
   - English
   - 简体中文  
   Persist the preference, apply it at launch and on change, and localize pages, service-card widget copy, error toasts, and provider profile descriptions.
2. **Verification loop without device CI** — Align the ArkTS contract harness with Swift request assertions (method / URL / header patterns), and fail `verify-provider-parity.sh` when a contract fixture case is missing from `CONTRACT_CASES`. CI continues to skip device-side ohosTest.

## Non-goals

- Running ohosTest / Hypium on GitHub Actions (no emulator/device in CI).
- Mirroring Aggregation / Alerts engines into ArkTS (separate track).
- Changing macOS i18n (already shipped via `AppLanguage` / `L10n` / Settings).
- Translating provider API-sourced metric labels carried in snapshots.
- Auto-discovering or generating `CONTRACT_CASES`.
- Adding new providers or expanding the spec schema.

## Background

- macOS already has `AppLanguagePreference` (`system` / `english` / `chinese`), `AppLanguage`, and an in-app `L10n` catalog. Roadmap item “Internationalization foundation” is complete on macOS; HarmonyOS remains Chinese-hardcoded in many places and only partially uses `$r('app.string.*')`.
- HarmonyOS theme switching already uses `ThemeStore` + `applyThemeMode` (`setColorMode`) + an Index overflow menu. Language should mirror that seam.
- Spec `profileDescription` intentionally returns stable L10n key tokens on ArkTS (platform-difference whitelist #1) because UI did not render them. Closing that gap is part of this work.
- ArkTS `Contract.test.ets` records headers but asserts only URL sequence and that methods are GET (whitelist #4 / `Contracts/README.md`). Swift asserts header patterns (`"Bearer"` = scheme prefix; other values exact).
- CI landscape (as of 2026-08-02):
  - `ci.yml` (macos-14): `swift test`, `verify-provider-parity.sh`, `ProviderParityTests.sh`, and other ScriptTests including `GitHubActionsTests.sh`.
  - `quality.yml` (ubuntu, **new**): actionlint / zizmor / ShellCheck on `scripts/` + `Tests/**/*.sh`, gitleaks, and a dedicated `provider-contract` job that runs `verify-provider-parity.sh` + `ProviderParityTests.sh` on every PR / push to `main` / `merge_group`.
  - `harmonyos.yml` (ubuntu + OHOS SDK): sync contracts, `verify-provider-parity.sh`, HAP build; path filters include `Contracts/**`, `HarmonyOS/**`, and `scripts/verify-provider-parity.sh`. Still **does not** run ohosTest.
- Extending `verify-provider-parity.sh` therefore lands automatically in Quality + CI + HarmonyOS; no new workflow file is required. New bash must stay ShellCheck-clean at `--severity=warning` (Quality `static` job).

## Approach summary

| Area | Choice |
| --- | --- |
| i18n storage / apply | Resource qualifiers + `LanguageStore` + `i18n.System.setAppPreferredLanguage` (or SDK-equivalent), patterned on theme |
| i18n copy source | `resources/base` (zh) + `resources/en_US` (en); keep existing `$r` call sites |
| Profile copy | Keep token-returning `profileDescription`; add UI resolver to localized strings |
| Harness | Record full request triples; assert like Swift |
| Static gate | Extend `verify-provider-parity.sh` to require `CONTRACT_CASES` coverage (and step URL sync with requests fixtures) |

---

## Part A — HarmonyOS i18n

### A.1 Persistence: `LanguageStore`

- New module: `HarmonyOS/entry/src/main/ets/storage/LanguageStore.ets`.
- Preference type: `'system' | 'english' | 'chinese'` (default `'system'`).
- Same preferences file as theme: `quotaglance_store`, key `app_language_v1`.
- Unrecognized values self-heal to `'system'` (same pattern as `ThemeStore`).

### A.2 Apply: `LanguageUtils`

- New module: `HarmonyOS/entry/src/main/ets/utils/LanguageUtils.ets`.
- `applyLanguage(preference)` using `@kit.LocalizationKit` `i18n.System.setAppPreferredLanguage`:
  - `english` → `'en-US'`.
  - `chinese` → `'zh-Hans'`.
  - `system` → restore follow-system behavior on SDK 6.1.1 (preferred: clear override if the API supports it; otherwise set to the device’s current system language and document the residual difference in `HarmonyOS/AGENTS.md`).
- Call from:
  - `EntryAbility.onCreate` (with theme restore).
  - Index language menu selection (immediate apply + UI refresh).
- Rely on configuration update / `@Watch` / page re-render so `$r` strings refresh. If `onConfigurationUpdate` is missing, add the same re-apply pattern used for theme background.

### A.3 Resource layout

- Keep Chinese as default in `entry/src/main/resources/base/element/string.json`.
- Add `entry/src/main/resources/en_US/element/string.json` with the **same key set** and English values.
- Mirror widget-facing AppScope strings that are user-visible (`AppScope/resources/base` + `en_US` as needed).
- Move hardcoded Chinese currently outside string resources into keys, including at least:
  - `SnapshotStore` widget status / empty / failure strings
  - `EntryFormAbility` loading placeholder
  - Screensaver weekday/date formatting (prefer locale-aware date APIs over translated literal fragments where practical)
  - Any remaining user-visible literals in pages/components discovered during implementation
- New keys for language UI: `language`, `language_system`, `language_english`, `language_chinese` (names may follow existing `theme_*` snake_case convention).
- New keys for profile-description templates matching Swift `L10n` profile subset (`notDetected`, `chinaCNY`, `internationalUSD`, `globalCredential`, `regionCredential`, region/credential display names as needed).

**Key parity rule:** every key present in `base/element/string.json` that is user-visible must exist in `en_US`. Prefer an automated check (ScriptTest or a section in `verify-provider-parity.sh` / a small dedicated script invoked from Quality or CI) so English key drift fails in the same Quality/CI loops that already gate parity.

### A.4 Profile description resolver

- Keep `ProviderDescriptor.profileDescription` returning stable tokens (contract / engine unchanged), e.g. `regionCredential:china:standard`, `notDetected`, credential-kind tokens.
- Add `utils/ProfileDescriptionL10n.ets` that maps token → localized string via `$r` / `resourceManager`, mirroring Swift argument substitution for `regionCredential` / region+kind styles.
- Call sites: account editor / account detail / any UI that shows profile copy.
- Keep whitelist #1 as an explicit seam: Swift resolves copy inside `ProviderDescriptor.profileDescription`; ArkTS descriptor still returns tokens and UI resolves via `ProfileDescriptionL10n`. Document that both end on the same key set and visible strings.

### A.5 Error mapping

- `ErrorMapping.friendlyErrorText` already uses `$r('app.string.err_*')`. Ensure those keys exist in `en_US` with English copy.
- No change to error token contract table.

### A.6 UI entry point

- Index header area: language menu adjacent to existing theme menu (same interaction pattern: checkmark, accent color, `bindMenu`).
- Selecting a mode saves via `LanguageStore`, calls `applyLanguage`, refreshes dependent `@State` if needed so menus/labels update immediately.

### A.7 Widget / FormExtension

- Widget texts built in `SnapshotStore` / `EntryFormAbility` must read from resource manager **after** preferred language is applied for the app process.
- FormExtension may run in a separate process: on update, read `LanguageStore` (or shared preferences) and call `applyLanguage` before formatting card strings so card language matches the app preference even when the system language differs.

---

## Part B — Verification loop

### B.1 Harness: request assertions

In `HarmonyOS/entry/src/ohosTest/ets/test/Contract.test.ets`:

- Change the stub fetcher to record `{ method: 'GET', url, headers }` (method is always GET today; still assert against fixture `method`).
- Replace `assertRequestUrls` with `assertRequests` matching Swift `expectRequests`:
  - Equal count and order.
  - `method` and `url` exact match.
  - For each header in the fixture: `"Bearer"` ⇒ value has prefix `Bearer `; otherwise exact string match.
  - Headers not listed in the fixture are unchecked.
- Skip assertion when `<case>-requests.json` is absent (same as today / Swift).

### B.2 Static gate: `CONTRACT_CASES` coverage

Extend `scripts/verify-provider-parity.sh`:

1. **Coverage:** For every provider directory under `Contracts/Providers/` and every distinct case name inferred from `*-expected.json` (same discovery rules as existing fixture completeness check), require a matching entry in `Contract.test.ets` `CONTRACT_CASES` with the same logical provider id and case `name`.
2. **Step URLs:** For each `CONTRACT_CASES` entry that has a requests fixture, require `steps[].url` sequence to equal the fixture’s `url` sequence (order-sensitive). Prevents stale hardcoded steps.

Parse strategy: lightweight `rg`/sed extraction of `name: '...'` / `provider: '...'` blocks is acceptable; keep the check deterministic and fail-fast with clear messages.

### B.3 Tests and CI wiring

- **No new workflow.** Coverage / step-URL checks live inside `verify-provider-parity.sh` and are exercised by existing callers:
  - Quality `provider-contract` (every PR)
  - CI `verify` (macos)
  - HarmonyOS `build` (when HarmonyOS/Contracts/parity script paths change)
- `Tests/ScriptTests/ProviderParityTests.sh`: **required** negative case — temporarily remove or comment out one `CONTRACT_CASES` entry (or otherwise break coverage), assert the parity script fails, restore via the existing backup/trap pattern (same style as tampered spec-copy tests). Quality already runs this script, so the red-path is CI-gated.
- `Tests/ScriptTests/GitHubActionsTests.sh`: already asserts Quality + CI + HarmonyOS invoke `verify-provider-parity.sh`; only extend if a *new* workflow step/name is introduced (not expected).
- Do **not** add ohosTest / Hypium / emulator steps to any workflow.
- ShellCheck: keep new parity-script bash idiomatic so Quality `static` stays green.

### B.4 Documentation

- `Contracts/README.md`: state that **both** harnesses assert header patterns.
- `HarmonyOS/AGENTS.md`: update whitelist #4 (header assertion parity achieved) and CI note (static coverage gate added; ohosTest still local-only).
- `AGENTS.md`: mention the new coverage check in the verification / parity description.
- `docs/roadmap.md`: mark macOS i18n complete; note HarmonyOS i18n + verification-loop work; treat GitHub Actions / Quality workflow as landed rather than “current delivery.”

---

## File touch list (expected)

**Create**

- `HarmonyOS/entry/src/main/ets/storage/LanguageStore.ets`
- `HarmonyOS/entry/src/main/ets/utils/LanguageUtils.ets`
- `HarmonyOS/entry/src/main/ets/utils/ProfileDescriptionL10n.ets`
- `HarmonyOS/entry/src/main/resources/en_US/element/string.json`
- Possibly `HarmonyOS/AppScope/resources/en_US/element/string.json`
- This design doc; later plan under `docs/superpowers/plans/`

**Modify**

- `EntryAbility.ets`, `EntryFormAbility.ets`, `Index.ets`, account pages/components as needed
- `SnapshotStore.ets`, screensaver / other hardcoded UI strings
- `ErrorMapping.ets` only if new keys or signatures needed
- `Contract.test.ets`
- `scripts/verify-provider-parity.sh`
- ScriptTests / AGENTS / Contracts README / roadmap as above
- `UsageProvider.ets` / `SpecDrivenProvider.ets` comments only (behavior of token return stays)

---

## Acceptance criteria

1. HarmonyOS language menu offers System / English / 简体中文; preference survives relaunch.
2. Switching to English updates main UI, account flows, and error toasts to English; Chinese restores; System follows device.
3. Profile descriptions render localized sentences/phrases, not raw tokens, in the account UI surfaces that show them.
4. Widget empty/failure/status strings follow the app language preference.
5. `en_US` string keys cover all user-visible keys used from `base`.
6. `Contract.test.ets` asserts request method, URL, and header patterns identically to Swift semantics (verified locally with ohosTest when a device/simulator is available).
7. Removing one `CONTRACT_CASES` entry causes `bash scripts/verify-provider-parity.sh` to fail; `ProviderParityTests.sh` covers that red path; the current tree passes.
8. Quality / CI / HarmonyOS workflows need no structural change; all three stay green (parity + ShellCheck) after the script extension.
9. Docs updated: whitelist #1/#4, Contracts README header section, roadmap note (Quality CI acknowledged as shipped).

## Risks and open implementation details

- Exact “clear preferred language / follow system” API on SDK 6.1.1 must be verified in code; document any residual platform difference.
- FormExtension process isolation may require applying language on every card update path.
- Large `string.json` English pass is mechanical but must not miss keys; automate key-set equality if feasible.
- Screensaver and number/date formatting should use locale-aware APIs where possible to avoid brittle translated templates.

## Out-of-scope follow-ups

- Device CI for ohosTest.
- Aggregation / Alerts ArkTS modules + fixture sync.
- Unifying Swift “resolve inside descriptor” vs ArkTS “resolve in UI” into identical call shapes (optional later deepening).
- Auto-discovery of contract cases from the filesystem.
