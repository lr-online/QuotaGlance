# HarmonyOS Widget Account Swipe Design

## Goal

Fix HarmonyOS small and medium service cards so the whole card opens QuotaGlance on tap, while horizontal swipes change the card's selected registered account without opening the app.

## Interaction

- The footer action button is removed from both compact (1*2/2*2) and list (2*4/4*4) layouts.
- A tap on any card surface posts the existing router action. The existing form binding resolution continues to route aggregate cards to the overview and account cards to account detail.
- A horizontal swipe is recognized only when the horizontal displacement is at least 48vp and larger than the vertical displacement. A left swipe selects the next enabled account; a right swipe selects the previous enabled account. Accounts are ordered by `AccountStore.load()` (`sortOrder`). Selection wraps at both ends.
- An aggregate card has no current account. A left swipe selects the first enabled account and a right swipe selects the last enabled account. With no enabled accounts, the gesture is a no-op.
- After a selection, the binding is persisted and the current form is republished through `updateFormCard`. An in-flight update ignores additional swipes until it completes.

## Architecture

`WidgetCard` owns only gesture recognition and the tap router action. A small pure navigation helper computes the adjacent account from a list, current id, and direction. `CardUpdater` loads enabled accounts, applies the helper, writes the binding through `FormBindingStore`, and refreshes the form. The existing `EntryAbility` deep-link behavior remains unchanged.

## Error handling

Selection failures are best-effort: the original binding remains in storage if persistence or republishing fails, and the error is logged by `CardUpdater`. The widget never displays a transient button or an invalid account id.

## Verification

- Add pure tests for ordered filtering, wrapping, aggregate entry, and empty-account no-op.
- Run the HarmonyOS parity check and the available HAP build. If the local DevEco toolchain is unavailable, record that limitation and rely on the CI workflow path.
