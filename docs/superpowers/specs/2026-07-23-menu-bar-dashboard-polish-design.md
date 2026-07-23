# QuotaGlance Menu Bar Dashboard Polish Design

Status: Approved for written-spec review
Date: 2026-07-23

## Objective

Improve the existing menu bar dashboard so balances, quota consumption, and
recent usage can be scanned quickly without expanding the phase-one product
scope. The change keeps the current native macOS panel, provider integration,
refresh behavior, and persisted data formats.

## Scope

This change includes:

- a balance-led single-account layout;
- concise two-decimal currency formatting for dashboard values;
- quota usage progress when valid used and limit values exist;
- a readable chart containing at most the latest seven daily entries;
- the two highest-cost model rows for a selected account;
- up to five account balance rows in the all-accounts view;
- a footer containing Settings, freshness, and Quit;
- focused presentation tests and an installed-app visual verification pass.

This change does not include:

- API, credential, refresh scheduling, or shared snapshot changes;
- provider expansion;
- settings or widget redesign;
- localization;
- a new detail window or model browser.

## Layout

The panel remains 360 points wide and uses native macOS materials, semantic
colors, and system typography. Its sections are ordered as follows:

1. Account picker and manual refresh button.
2. Remaining balance, labeled `Remaining`, formatted to two decimal places.
3. Freshness or error status adjacent to the primary balance.
4. Quota progress with used and limit values when both values form a valid
   ratio.
5. Today's actual spend and request count in two columns.
6. A seven-day usage chart in chronological order.
7. Selection-specific details.
8. Settings, last successful refresh time, and Quit in the footer.

For a selected account, selection-specific details contain the two models with
the highest actual cost. For All Accounts, they contain up to five account rows
with display name, health status, and remaining balance. The latter replaces
the current attention-only list so healthy accounts are also useful in the
aggregate view.

## Formatting And Derived Presentation

Provider and snapshot money values retain their full decimal precision. A
dashboard-specific currency formatter renders visible monetary values with
exactly two fractional digits and grouping separators. This avoids changing
calculation or persistence semantics and does not force the same precision on
future detailed surfaces.

The quota progress indicator appears only when both `quotaUsed` and
`quotaLimit` exist and the limit is greater than zero. Its visual fraction is
clamped to the range from zero through one. If only one quota value exists, the
available value may still be shown as text, but no progress fraction is
invented.

Daily usage is stably ordered by its ISO provider date and then reduced to the
latest seven entries. The chart shows the day of month beneath each bar and uses a
hover tooltip containing the full provider date and formatted spend. If fewer
than seven entries exist, all available entries are shown. An unparseable date
retains its provider order and does not crash or resize the panel; it falls back
to a short, bounded label.

Model usage is ordered by actual cost descending. Entries without an actual
cost sort after entries with a cost, with the provider order retained for ties.
Only the first two entries are visible in the menu bar panel.

## Existing States

The current empty, loading, unavailable, partial, stale, low-balance, and
healthy states remain authoritative. Status color continues to be semantic:
green for healthy, amber for low, partial, or stale data, red for unavailable
data, and system neutral colors for ordinary structure.

Missing quota or model data does not turn an otherwise healthy snapshot into
an error. All Accounts continues to use aggregate balance, today metrics, and
daily usage; individual account health remains visible in its account rows.

## Architecture

The provider, refresh coordinator, Keychain storage, App Group snapshot, and
domain models do not change. Derived ordering, truncation, and formatting live
in the presentation boundary so `MenuBarDashboardView` remains focused on
layout. `UsageChartView` receives no more than seven chronologically ordered
entries and owns only bar rendering and bounded date labels.

The widget target continues using its existing presentation and formatting.
No shared snapshot version bump is required.

## Verification

Automated tests cover:

- dashboard currency formatting at two decimal places;
- chronological selection of the latest seven daily entries;
- fewer-than-seven and malformed-date input;
- descending model cost order, missing costs, and stable ties;
- quota progress for normal, over-limit, zero-limit, and missing-value cases;
- all-account rows containing healthy and unhealthy accounts.

After the full Swift test suite passes, the certificate-free local installer is
used to replace and relaunch `~/Applications/QuotaGlance.app`. The installed
menu bar panel is checked with live API Info data for readable currency values,
seven non-overlapping date labels, quota progress, two model rows, footer
actions, and unchanged refresh/error behavior.
