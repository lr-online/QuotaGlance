# HarmonyOS Widget Account Swipe Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make HarmonyOS small and medium cards open on tap, remove their footer button, and switch enabled accounts on horizontal swipe.

**Architecture:** Keep `WidgetCard` as a thin interaction surface. Add a pure account-selection helper; have `CardUpdater` own persistence and republishing so the card and app use the same binding format. The existing deep-link resolution remains the single tap routing path.

**Tech Stack:** HarmonyOS ArkTS, FormKit `formProvider`, ArkUI `PanGesture`, Hypium ohosTest.

---

### Task 1: Add pure account navigation rules

**Files:**
- Create: `HarmonyOS/entry/src/main/ets/widget/FormAccountNavigation.ets`
- Modify: `HarmonyOS/entry/src/ohosTest/ets/test/Ability.test.ets`

- [ ] **Step 1: Write the failing tests**

Add a `WidgetAccountNavigationTest` suite importing `selectAdjacentAccount`, with cases for disabled filtering and sort order, wrapping in both directions, aggregate entry (`undefined` current id), and an empty list returning `null`.

- [ ] **Step 2: Run the targeted ohosTest task when a device is available**

Run: `cd HarmonyOS && ./hvigorw test --no-daemon`

Expected: the new suite fails to compile because the helper does not exist yet. If no simulator/device or Hvigor test task is available, record the environment limitation and continue with the static checks.

- [ ] **Step 3: Implement the pure helper**

Export `WidgetAccount { id: string; isEnabled: boolean; sortOrder: number }`, `SwipeDirection = 'left' | 'right'`, and `selectAdjacentAccount(accounts, currentAccountId, direction)`. Filter enabled accounts, sort ascending by `sortOrder`, return `null` for no accounts, use index `-1` for an unset/missing current id, and choose index `0` for left or last index for right from aggregate; otherwise increment for left and decrement for right with modulo wrapping.

- [ ] **Step 4: Run the targeted tests/static type checks**

Run: `cd HarmonyOS && ./hvigorw test --no-daemon` when available, then `bash scripts/verify-provider-parity.sh`. Expected: navigation tests pass and parity remains green.

- [ ] **Step 5: Commit**

```bash
git add HarmonyOS/entry/src/main/ets/widget/FormAccountNavigation.ets HarmonyOS/entry/src/ohosTest/ets/test/Ability.test.ets
git commit -m "test(harmonyos): define widget account swipe selection"
```

### Task 2: Persist and republish the selected account

**Files:**
- Modify: `HarmonyOS/entry/src/main/ets/services/CardUpdater.ets`

- [ ] **Step 1: Add `switchFormAccount`**

Import the pure helper, load the form binding and accounts, call `selectAdjacentAccount` with the current bound id, and return without writing when it returns `null`. Otherwise call `FormBindingStore.setAccount(formId, selected.id)` followed by `updateFormCard(context, formId)` inside the existing best-effort logging boundary.

- [ ] **Step 2: Verify the service compiles with existing consumers**

Run: `bash scripts/verify-provider-parity.sh`. Expected: no generated resources change and the service remains the only writer of updated card payloads.

- [ ] **Step 3: Commit**

```bash
git add HarmonyOS/entry/src/main/ets/services/CardUpdater.ets
git commit -m "feat(harmonyos): republish widget after account swipe"
```

### Task 3: Replace the button with tap and swipe interactions

**Files:**
- Modify: `HarmonyOS/entry/src/main/ets/widget/pages/WidgetCard.ets`

- [ ] **Step 1: Add gesture state and handlers**

Import `common` and `switchFormAccount`. Add `@State private swipeOffsetX: number = 0`, `@State private swipeOffsetY: number = 0`, and a private `switchingAccount` guard. Record offsets in `PanGesture().onActionUpdate`, and on end/cancel reset offsets; on end invoke `switchFormAccount` only when horizontal movement is at least 48vp and dominates vertical movement. The handler uses `getContext(this) as common.Context` and the form id.

- [ ] **Step 2: Make the root card clickable and remove `footerButton`**

Delete `open_app`/`查看详情` footer rendering. Attach `.onClick(() => this.openApp())` and `.gesture(this.accountSwipeGesture())` to the root `Column`, keeping the existing compact/list body content and stable dimensions.

- [ ] **Step 3: Run formatting/parity checks**

Run: `bash scripts/verify-provider-parity.sh`. Expected: parity passes; only the widget interaction code and service/helper files are changed.

- [ ] **Step 4: Commit**

```bash
git add HarmonyOS/entry/src/main/ets/widget/pages/WidgetCard.ets
git commit -m "fix(harmonyos): make widget cards tappable and swipeable"
```

### Task 4: Build and publish

**Files:**
- No additional source files.

- [ ] **Step 1: Run available validation**

Run: `bash scripts/verify-provider-parity.sh`; `bash scripts/build-harmonyos.sh` with `HARMONYOS_SKIP_SIGN=1` when `DEVECO_SDK_HOME`/`HOS_SDK_HOME`, `ohpm`, and `hvigorw` are available; and `swift test` only if the host has the Swift/XCTest toolchain. Record unavailable toolchains explicitly.

- [ ] **Step 2: Inspect scope and commit any remaining changes**

Run: `git status --short`, `git diff origin/main...HEAD --stat`, and confirm only the design/plan docs plus widget helper, service, UI, and tests are included.

- [ ] **Step 3: Push and open a draft PR**

```bash
git push -u origin codex/harmonyos-widget-account-swipe
gh pr create --draft --base main --head codex/harmonyos-widget-account-swipe --title "[codex] Fix HarmonyOS widget card layout and account swipe" --body-file /tmp/quotaglance-widget-pr.md
```

The PR body must state that the footer button was removed, tap now opens the app, horizontal swipes cycle enabled accounts, the previous binding/deep-link path is reused, and list the exact validation results or environment gaps.
