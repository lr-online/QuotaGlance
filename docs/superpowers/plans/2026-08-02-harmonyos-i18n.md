# HarmonyOS Full i18n Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add HarmonyOS System / English / 简体中文 language preference with resource-based localization for pages, widget copy, errors, and provider profile descriptions.

**Architecture:** Mirror theme: `LanguageStore` persists preference; `LanguageUtils.applyLanguage` calls `i18n.System.setAppPreferredLanguage`; Chinese stays in `resources/base`, English in `resources/en_US`. `profileDescription` keeps returning tokens; `ProfileDescriptionL10n` resolves them at UI. Widget/FormExtension applies language before formatting card strings.

**Tech Stack:** ArkTS, `@kit.LocalizationKit` (`i18n.System`), HarmonyOS resource qualifiers, Preferences (`quotaglance_store`).

**Spec:** `docs/superpowers/specs/2026-08-02-harmonyos-i18n-and-verification-design.md` Part A.

**Sibling plan:** `docs/superpowers/plans/2026-08-02-harmonyos-verification-loop.md` (Part B). Prefer shipping verification first; this plan does not depend on it except shared roadmap edits.

## Global Constraints

- Do **not** change macOS `L10n` / `AppLanguage` behavior.
- Do **not** change SpecDrivenProvider `profileDescription` token return shape (whitelist #1 seam stays: Swift resolves in descriptor; ArkTS resolves in UI).
- Language tags: `english` → `en-US`, `chinese` → `zh-Hans`; `system` restores follow-system on SDK 6.1.1 (document residual difference in `HarmonyOS/AGENTS.md` if clear-override API is unavailable).
- `base` and `en_US` string key sets must stay equal for entry module strings (automated check).
- Provider brand names stay English; do not translate API-sourced snapshot metric labels.
- No new GitHub workflow; string-key check must run via ScriptTest / parity path already covered by Quality or CI.

---

### Task 1: `LanguageStore` + `LanguageUtils`

**Files:**
- Create: `HarmonyOS/entry/src/main/ets/storage/LanguageStore.ets`
- Create: `HarmonyOS/entry/src/main/ets/utils/LanguageUtils.ets`

**Interfaces:**
- Produces:
  - `export type LanguagePreference = 'system' | 'english' | 'chinese'`
  - `LanguageStore.create(context): Promise<LanguageStore>`
  - `load(): Promise<LanguagePreference>`, `save(pref: LanguagePreference): Promise<void>`
  - `applyLanguage(preference: LanguagePreference): void`

- [ ] **Step 1: Create `LanguageStore.ets`**

```typescript
import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';

// Manual language override: 跟随系统 (default) / English / 简体中文.
// Same preferences file as ThemeStore under 'app_language_v1'.
export type LanguagePreference = 'system' | 'english' | 'chinese';

const STORE_NAME = 'quotaglance_store';
const LANGUAGE_KEY = 'app_language_v1';
const DEFAULT_PREF: LanguagePreference = 'system';

export class LanguageStore {
  private readonly store: preferences.Preferences;

  private constructor(store: preferences.Preferences) {
    this.store = store;
  }

  static async create(context: common.Context): Promise<LanguageStore> {
    const store = await preferences.getPreferences(context, { name: STORE_NAME });
    return new LanguageStore(store);
  }

  async load(): Promise<LanguagePreference> {
    const raw = await this.store.get(LANGUAGE_KEY, DEFAULT_PREF) as string;
    if (raw === 'english' || raw === 'chinese') {
      return raw;
    }
    return DEFAULT_PREF;
  }

  async save(preference: LanguagePreference): Promise<void> {
    await this.store.put(LANGUAGE_KEY, preference);
    await this.store.flush();
  }
}
```

- [ ] **Step 2: Create `LanguageUtils.ets`**

```typescript
import { i18n } from '@kit.LocalizationKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { LanguagePreference } from '../storage/LanguageStore';

const DOMAIN = 0x0000;
const TAG = 'QuotaGlanceLanguage';

// Maps persisted preference onto app preferred language (API 11+).
// english → en-US, chinese → zh-Hans.
// system → clear override when possible; otherwise set to the device
// system language so UI still tracks the device until next relaunch.
export function applyLanguage(preference: LanguagePreference): void {
  try {
    if (preference === 'english') {
      i18n.System.setAppPreferredLanguage('en-US');
      return;
    }
    if (preference === 'chinese') {
      i18n.System.setAppPreferredLanguage('zh-Hans');
      return;
    }
    // Follow system: prefer empty / clear if SDK accepts it; fallback to
    // current system language tag so resources stop forcing en/zh override.
    const systemTag = i18n.System.getSystemLanguage();
    i18n.System.setAppPreferredLanguage(systemTag);
  } catch (error) {
    hilog.warn(DOMAIN, TAG, 'setAppPreferredLanguage failed: %{public}s', (error as Error).message);
  }
}
```

During implementation, verify against SDK 6.1.1 whether an empty string or dedicated clear API exists; if `setAppPreferredLanguage(systemTag)` does not re-follow future system changes, document that residual difference under `HarmonyOS/AGENTS.md` platform-difference whitelist.

- [ ] **Step 3: Commit**

```bash
git add HarmonyOS/entry/src/main/ets/storage/LanguageStore.ets \
  HarmonyOS/entry/src/main/ets/utils/LanguageUtils.ets
git commit -m "$(cat <<'EOF'
feat(harmonyos): add LanguageStore and applyLanguage utility

EOF
)"
```

---

### Task 2: English resources + new string keys + key-set gate

**Files:**
- Modify: `HarmonyOS/entry/src/main/resources/base/element/string.json` (add new keys only)
- Create: `HarmonyOS/entry/src/main/resources/en_US/element/string.json`
- Create: `Tests/ScriptTests/HarmonyOSStringParityTests.sh`
- Modify: `Tests/ScriptTests/GitHubActionsTests.sh` only if CI must list the new ScriptTest—**prefer** invoking the new script from `ci.yml` via a new step **or** call it from an existing ScriptTest aggregator. Minimal approach: add a step in `.github/workflows/ci.yml` next to other ScriptTests, and assert that step in `GitHubActionsTests.sh`.

**Interfaces:**
- Produces: identical `name` sets in `base` and `en_US` string.json; new keys listed below

- [ ] **Step 1: Add Chinese keys to `base/element/string.json`**

Append (snake_case, matching `theme_*`):

| name | zh value |
| --- | --- |
| `language` | `语言` |
| `language_system` | `跟随系统` |
| `language_english` | `English` |
| `language_chinese` | `简体中文` |
| `widget_balance_unconfigured` | `未配置` |
| `widget_status_prompt_key` | `打开应用录入 API Key` |
| `widget_status_ok` | `正常` |
| `widget_status_unavailable` | `服务不可用` |
| `widget_loading` | `加载中…` |
| `l10n_not_detected` | `未检测` |
| `l10n_china_cny` | `中国 / CNY` |
| `l10n_international_usd` | `国际 / USD` |
| `l10n_global_credential` | `全球 / %s` |
| `l10n_region_credential` | `%s / %s` |
| `l10n_global` | `全球` |
| `l10n_china` | `中国` |
| `l10n_international` | `国际` |
| `l10n_standard_key` | `标准密钥` |
| `l10n_management_key` | `管理密钥` |
| `l10n_token_plan` | `Token 套餐` |
| `profile_label` | `配置` |

Note: `stale_text` / `updated_prefix` already exist—reuse them in SnapshotStore instead of duplicating.

- [ ] **Step 2: Create `en_US/element/string.json`**

Copy **every** key from `base/element/string.json` with English values. Mirror Swift `L10n` where applicable (errors, theme, overview, account editor). Examples:

- `manage_accounts` → `Accounts`
- `err_invalid_credential` → `API key is invalid or expired. Check and try again.`
- `theme_system` → `System`
- `l10n_region_credential` → `%s / %s`
- `language_system` → `System`
- Keep brand `QuotaGlance` untranslated.

AppScope only has `app_name` = `QuotaGlance`; skip AppScope `en_US` unless more user-visible AppScope strings appear.

- [ ] **Step 3: Write `HarmonyOSStringParityTests.sh`**

```bash
#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
BASE="$ROOT_DIR/HarmonyOS/entry/src/main/resources/base/element/string.json"
EN="$ROOT_DIR/HarmonyOS/entry/src/main/resources/en_US/element/string.json"

fail() { echo "FAIL: $*" >&2; exit 1; }
[[ -f "$BASE" ]] || fail "missing $BASE"
[[ -f "$EN" ]] || fail "missing $EN"

python3 - "$BASE" "$EN" <<'PY'
import json, sys
base = {e["name"] for e in json.load(open(sys.argv[1]))["string"]}
en = {e["name"] for e in json.load(open(sys.argv[2]))["string"]}
missing = sorted(base - en)
extra = sorted(en - base)
if missing or extra:
    if missing:
        print("missing in en_US:", ", ".join(missing), file=sys.stderr)
    if extra:
        print("extra in en_US:", ", ".join(extra), file=sys.stderr)
    sys.exit(1)
print(f"OK: {len(base)} string keys match between base and en_US")
PY
```

`chmod +x` the script.

- [ ] **Step 4: Wire into CI + GitHubActionsTests**

Add to `.github/workflows/ci.yml` after an existing ScriptTest step:

```yaml
      - name: Verify HarmonyOS string key parity
        run: /bin/bash Tests/ScriptTests/HarmonyOSStringParityTests.sh
```

In `Tests/ScriptTests/GitHubActionsTests.sh`, assert:

```bash
rg -Fq "Tests/ScriptTests/HarmonyOSStringParityTests.sh" "$CI_WORKFLOW" \
  || fail "CI workflow missing HarmonyOS string parity test"
```

- [ ] **Step 5: Run tests**

```bash
bash Tests/ScriptTests/HarmonyOSStringParityTests.sh
bash Tests/ScriptTests/GitHubActionsTests.sh
```

Expected: both pass.

- [ ] **Step 6: Commit**

```bash
git add HarmonyOS/entry/src/main/resources/base/element/string.json \
  HarmonyOS/entry/src/main/resources/en_US/element/string.json \
  Tests/ScriptTests/HarmonyOSStringParityTests.sh \
  Tests/ScriptTests/GitHubActionsTests.sh \
  .github/workflows/ci.yml
git commit -m "$(cat <<'EOF'
feat(harmonyos): add en_US strings and key-parity ScriptTest

EOF
)"
```

---

### Task 3: Apply language at launch + Index menu

**Files:**
- Modify: `HarmonyOS/entry/src/main/ets/entryability/EntryAbility.ets`
- Modify: `HarmonyOS/entry/src/main/ets/pages/Index.ets`

**Interfaces:**
- Consumes: `LanguageStore`, `applyLanguage`, `$r('app.string.language*')`

- [ ] **Step 1: Restore language in `EntryAbility.onCreate`**

Alongside theme restore:

```typescript
import { LanguagePreference, LanguageStore } from '../storage/LanguageStore';
import { applyLanguage } from '../utils/LanguageUtils';

// inside onCreate, after or parallel to ThemeStore:
LanguageStore.create(this.context)
  .then((store: LanguageStore) => store.load())
  .then((preference: LanguagePreference) => {
    applyLanguage(preference);
  })
  .catch((error: Object) => {
    hilog.warn(DOMAIN, 'QuotaGlance', 'language restore failed: %{public}s', (error as Error).message);
  });
```

- [ ] **Step 2: Add language state + menu on Index**

Mirror `themeMode` / `themeMenu` / `selectTheme`:

```typescript
@State languagePreference: LanguagePreference = 'system';

// in reload / aboutToAppear path that loads theme:
const languageStore = await LanguageStore.create(context);
this.languagePreference = await languageStore.load();

private selectLanguage(preference: LanguagePreference): void {
  if (preference === this.languagePreference) {
    return;
  }
  this.languagePreference = preference;
  const context = getContext(this) as common.UIAbilityContext;
  LanguageStore.create(context)
    .then((store: LanguageStore) => store.save(preference))
    .then(() => {
      applyLanguage(preference);
      // Bump a @State tick if needed so $r labels in this page refresh.
      this.syncTick += 1;
    })
    .catch((error: Object) => {
      hilog.error(DOMAIN, TAG, 'save language failed: %{public}s', (error as Error).message);
    });
}

@Builder
languageMenuItem(preference: LanguagePreference, label: Resource) {
  // Same layout as themeMenuItem (checkmark + accent)
}

@Builder
languageMenu() {
  this.languageMenuItem('system', $r('app.string.language_system'))
  this.languageMenuItem('english', $r('app.string.language_english'))
  this.languageMenuItem('chinese', $r('app.string.language_chinese'))
}
```

In the app bar `Row`, insert before or after the theme chip:

```typescript
Text($r('app.string.language'))
  .fontSize(14)
  .fontColor($r('app.color.accentTeal'))
  .chipStyle()
  .margin({ right: 8 })
  .bindMenu(this.languageMenu(), {
    backgroundColor: $r('app.color.cardBackground'),
    borderRadius: 12,
    placement: Placement.Bottom,
    enableArrow: false
  })
```

- [ ] **Step 3: Manual check**

Build HAP (`bash scripts/build-harmonyos.sh` when SDK available). Switch language in UI; confirm chrome strings flip; relaunch and confirm preference sticks.

- [ ] **Step 4: Commit**

```bash
git add HarmonyOS/entry/src/main/ets/entryability/EntryAbility.ets \
  HarmonyOS/entry/src/main/ets/pages/Index.ets
git commit -m "$(cat <<'EOF'
feat(harmonyos): wire language preference into launch and Index menu

EOF
)"
```

---

### Task 4: Widget / SnapshotStore / FormExtension localization

**Files:**
- Modify: `HarmonyOS/entry/src/main/ets/storage/SnapshotStore.ets`
- Modify: `HarmonyOS/entry/src/main/ets/entryformability/EntryFormAbility.ets`

**Interfaces:**
- Change `formatSnapshotTexts` to accept `common.Context` (or `resourceManager`) so it can call `getStringSync`.

- [ ] **Step 1: Localize `formatSnapshotTexts`**

```typescript
import { common } from '@kit.AbilityKit';

export function formatSnapshotTexts(
  context: common.Context,
  stored: StoredSnapshot | null
): Record<string, string> {
  const rm = context.resourceManager;
  if (!stored || stored.snapshot.balances.length === 0) {
    return {
      'balanceText': rm.getStringSync($r('app.string.widget_balance_unconfigured').id),
      'statusText': rm.getStringSync($r('app.string.widget_status_prompt_key').id),
      'updatedAtText': ''
    };
  }
  // ...
  texts['statusText'] = rm.getStringSync($r('app.string.widget_status_ok').id);
  if (stored.isStale) {
    texts['statusText'] = rm.getStringSync($r('app.string.stale_text').id);
  } else if (snapshot.providerStatus !== 'active') {
    texts['statusText'] = rm.getStringSync($r('app.string.widget_status_unavailable').id);
  }
  // formatTime: prefix via updated_prefix
}
```

Update every call site of `formatSnapshotTexts` to pass `context`.

- [ ] **Step 2: Apply language in `EntryFormAbility` before formatting**

```typescript
import { LanguageStore } from '../storage/LanguageStore';
import { applyLanguage } from '../utils/LanguageUtils';

// in refreshForm / onAddForm path:
const languageStore = await LanguageStore.create(this.context);
applyLanguage(await languageStore.load());
// placeholder:
'balanceText': this.context.resourceManager.getStringSync($r('app.string.widget_loading').id)
// after load:
const texts = formatSnapshotTexts(this.context, stored);
```

- [ ] **Step 3: Commit**

```bash
git add HarmonyOS/entry/src/main/ets/storage/SnapshotStore.ets \
  HarmonyOS/entry/src/main/ets/entryformability/EntryFormAbility.ets
# plus any other formatSnapshotTexts call sites
git commit -m "$(cat <<'EOF'
feat(harmonyos): localize widget snapshot and form placeholder strings

EOF
)"
```

---

### Task 5: `ProfileDescriptionL10n` + UI surfaces

**Files:**
- Create: `HarmonyOS/entry/src/main/ets/utils/ProfileDescriptionL10n.ets`
- Modify: `HarmonyOS/entry/src/main/ets/pages/AccountEditorPage.ets`
- Modify: `HarmonyOS/entry/src/main/ets/pages/AccountsPage.ets` and/or `AccountDetailPage.ets` / `AccountDetailView.ets` (show resolved profile for `account.detectedProfile`)
- Modify: `HarmonyOS/entry/src/main/ets/providers/UsageProvider.ets` and `SpecDrivenProvider.ets` (comments only—document UI resolution seam)
- Modify: `HarmonyOS/AGENTS.md` whitelist #1

**Interfaces:**
- Produces: `resolveProfileDescription(context: common.Context, token: string): string`
- Consumes: descriptor tokens from `providerDescriptor(...).profileDescription(profile?)`

- [ ] **Step 1: Implement resolver**

```typescript
import { common } from '@kit.AbilityKit';

function regionLabel(rm: resourceManager.ResourceManager, region: string): string {
  if (region === 'china') {
    return rm.getStringSync($r('app.string.l10n_china').id);
  }
  if (region === 'international') {
    return rm.getStringSync($r('app.string.l10n_international').id);
  }
  return rm.getStringSync($r('app.string.l10n_global').id);
}

function kindLabel(rm: resourceManager.ResourceManager, kind: string): string {
  if (kind === 'management') {
    return rm.getStringSync($r('app.string.l10n_management_key').id);
  }
  if (kind === 'tokenPlan') {
    return rm.getStringSync($r('app.string.l10n_token_plan').id);
  }
  return rm.getStringSync($r('app.string.l10n_standard_key').id);
}

export function resolveProfileDescription(context: common.Context, token: string): string {
  const rm = context.resourceManager;
  if (token === 'notDetected') {
    return rm.getStringSync($r('app.string.l10n_not_detected').id);
  }
  if (token === 'chinaCNY') {
    return rm.getStringSync($r('app.string.l10n_china_cny').id);
  }
  if (token === 'internationalUSD') {
    return rm.getStringSync($r('app.string.l10n_international_usd').id);
  }
  if (token === 'standard' || token === 'management' || token === 'tokenPlan') {
    return kindLabel(rm, token);
  }
  if (token.indexOf('globalCredential:') === 0) {
    const kind = token.substring('globalCredential:'.length);
    const template = rm.getStringSync($r('app.string.l10n_global_credential').id);
    return template.replace('%s', kindLabel(rm, kind));
  }
  if (token.indexOf('regionCredential:') === 0) {
    const parts = token.split(':'); // regionCredential, region, kind
    const region = parts[1] ?? 'global';
    const kind = parts[2] ?? 'standard';
    const template = rm.getStringSync($r('app.string.l10n_region_credential').id);
    return template.replace('%s', regionLabel(rm, region)).replace('%s', kindLabel(rm, kind));
  }
  if (token.indexOf('chinaCNY:') === 0 || token.indexOf('internationalUSD:') === 0) {
    // byRegion keys that append :kind — show base label + kind if needed
    const base = token.split(':')[0];
    const kind = token.split(':')[1];
    const head = resolveProfileDescription(context, base);
    return kind ? `${head} · ${kindLabel(rm, kind)}` : head;
  }
  return token;
}
```

Adjust branch handling to match **exact** tokens emitted by `makeDescriptor` in `SpecDrivenProvider.ets` (re-read that function before finalizing—`regionCredential:${region}:${kind}`, bare kinds, `byRegion` keys with optional `:kind`).

- [ ] **Step 2: Show on AccountEditor**

Under provider chips, when no profile yet:

```typescript
Text(resolveProfileDescription(
  getContext(this) as common.Context,
  providerDescriptor(getContext(this) as common.Context, this.selectedProvider)
    .profileDescription(undefined)
))
  .fontSize(12)
  .fontColor($r('app.color.textSecondary'))
```

- [ ] **Step 3: Show on account list/detail**

For each `Account` with `detectedProfile`, display:

```typescript
resolveProfileDescription(
  context,
  providerDescriptor(context, account.provider).profileDescription(account.detectedProfile)
)
```

Pick the densest existing secondary-line slot on `AccountsPage` or `AccountDetailView` header—do not invent a new card chrome.

- [ ] **Step 4: Docs**

Update whitelist #1 in `HarmonyOS/AGENTS.md`: descriptor returns tokens; UI resolves via `ProfileDescriptionL10n` / string resources; Swift resolves inside descriptor. Same key set / visible meaning.

Comment updates on `UsageProvider.ets` / `SpecDrivenProvider.ets` profileDescription notes.

- [ ] **Step 5: Commit**

```bash
git add HarmonyOS/entry/src/main/ets/utils/ProfileDescriptionL10n.ets \
  HarmonyOS/entry/src/main/ets/pages/AccountEditorPage.ets \
  HarmonyOS/entry/src/main/ets/pages/AccountsPage.ets \
  HarmonyOS/entry/src/main/ets/components/AccountDetailView.ets \
  HarmonyOS/entry/src/main/ets/providers/UsageProvider.ets \
  HarmonyOS/entry/src/main/ets/providers/SpecDrivenProvider.ets \
  HarmonyOS/AGENTS.md
# adjust paths to match files actually edited
git commit -m "$(cat <<'EOF'
feat(harmonyos): resolve profile description L10n tokens in UI

EOF
)"
```

---

### Task 6: Screensaver + remaining hardcoded UI strings

**Files:**
- Modify: `HarmonyOS/entry/src/main/ets/pages/ScreensaverPage.ets`
- Grep pass: `HarmonyOS/entry/src/main/ets/**/*.ets` for user-visible Chinese literals outside comments; migrate any remaining into `string.json` (both `base` and `en_US`) and re-run `HarmonyOSStringParityTests.sh`.

- [ ] **Step 1: Locale-aware date on screensaver**

Replace hardcoded `周${weekday}` construction with `Intl.DateTimeFormat` using the effective app locale (from preference / `i18n.System.getSystemLanguage()` after apply), or resource-backed weekday names only if Intl is awkward on the target API. Prefer one `DateTimeFormat` with `month`/`day`/`weekday`.

- [ ] **Step 2: Grep cleanup**

```bash
rg -n "[\u4e00-\u9fff]" HarmonyOS/entry/src/main/ets --glob '*.ets' \
  | rg -v "^\S+:\s*//" 
```

Migrate leftover user-facing literals; leave code comments alone.

- [ ] **Step 3: Re-run string parity + build**

```bash
bash Tests/ScriptTests/HarmonyOSStringParityTests.sh
bash scripts/build-harmonyos.sh   # when SDK available
```

- [ ] **Step 4: Commit**

```bash
git add HarmonyOS/entry/src/main/ets/pages/ScreensaverPage.ets \
  HarmonyOS/entry/src/main/resources/base/element/string.json \
  HarmonyOS/entry/src/main/resources/en_US/element/string.json
# plus any other files from the grep cleanup
git commit -m "$(cat <<'EOF'
feat(harmonyos): localize screensaver date and remaining UI copy

EOF
)"
```

---

### Task 7: Roadmap + final doc pass

**Files:**
- Modify: `docs/roadmap.md`
- Modify: `README.md` only if it still says HarmonyOS is “评估中” for localization/status (align one sentence if clearly stale)

- [ ] **Step 1: Roadmap**

- Mark macOS internationalization foundation **Completed**.
- Mark GitHub Actions / Quality workflow **Completed** (if not already by verification plan).
- Add HarmonyOS full i18n under Completed when this plan finishes; keep Aggregation/Alerts ArkTS mirror as open.

- [ ] **Step 2: Final verification checklist**

```bash
bash Tests/ScriptTests/HarmonyOSStringParityTests.sh
bash Tests/ScriptTests/GitHubActionsTests.sh
bash scripts/verify-provider-parity.sh
bash scripts/build-harmonyos.sh   # when SDK available
```

Manual: language menu System/English/中文; errors in English; profile text not raw tokens; widget strings follow preference.

- [ ] **Step 3: Commit**

```bash
git add docs/roadmap.md README.md
git commit -m "$(cat <<'EOF'
docs: mark HarmonyOS i18n complete on roadmap

EOF
)"
```

---

## i18n plan self-check

| Spec Part A requirement | Task |
| --- | --- |
| A.1 LanguageStore | Task 1 |
| A.2 LanguageUtils + launch apply | Tasks 1, 3 |
| A.3 en_US + new keys + key parity | Task 2 |
| A.4 ProfileDescriptionL10n + UI | Task 5 |
| A.5 Error mapping en_US | Task 2 |
| A.6 Index language menu | Task 3 |
| A.7 Widget / FormExtension | Task 4 |
| Screensaver / hardcoded cleanup | Task 6 |
| Docs / roadmap / whitelist #1 | Tasks 5, 7 |
| Acceptance 1–5, 9 | Tasks 1–7 |
