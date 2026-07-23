# Menu Bar Dashboard Polish Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the current dense menu bar dashboard with the approved balance-led layout while preserving provider, refresh, persistence, and widget behavior.

**Architecture:** Add a `MenuBarPresenter` in `QuotaGlanceCore` that wraps the existing `DashboardPresenter` and derives only menu-bar-specific quota progress, seven-day rows, top models, and account rows. Keep the widget on the existing `DashboardPresenter`, and keep raw `Money` precision unchanged by adding a separate two-decimal formatting entry point. SwiftUI consumes the derived presentation without sorting or truncating provider data itself.

**Tech Stack:** Swift 6, Swift Testing, SwiftUI, AppKit, Swift Package Manager, the existing certificate-free local build/install scripts.

---

## File Map

- Create `Sources/QuotaGlanceCore/Presentation/MenuBarPresentation.swift`: menu-bar-only presentation values and deterministic derivation.
- Modify `Sources/QuotaGlanceCore/Presentation/DashboardPresentation.swift`: add a two-decimal dashboard currency formatter without changing the existing precise formatter.
- Create `Tests/QuotaGlanceCoreTests/MenuBarPresentationTests.swift`: cover day ordering and labels, quota progress, model order, account rows, and edge cases.
- Modify `Tests/QuotaGlanceCoreTests/DashboardPresentationTests.swift`: prove dashboard formatting rounds to two decimals while the existing formatter retains precision.
- Modify `App/MenuBar/MenuBarDashboardView.swift`: implement the approved balance-led information hierarchy and footer.
- Modify `App/MenuBar/UsageChartView.swift`: render seven prepared day rows with bounded labels and complete tooltips.

### Task 1: Add Dashboard Currency Formatting

**Files:**
- Modify: `Tests/QuotaGlanceCoreTests/DashboardPresentationTests.swift`
- Modify: `Sources/QuotaGlanceCore/Presentation/DashboardPresentation.swift:107`

- [ ] **Step 1: Write the failing two-decimal formatting test**

Add this test beside `currencyFormattingPreservesDecimalPrecision`:

```swift
@Test("Dashboard currency formatting rounds to two decimals")
func dashboardCurrencyFormattingUsesTwoDecimals() {
    let formatted = MoneyFormatter.dashboardString(
        Money(
            amount: Decimal(string: "423.9753505")!,
            currency: "USD"
        ),
        locale: Locale(identifier: "en_US")
    )

    #expect(formatted == "$423.98")
}
```

- [ ] **Step 2: Run the focused test and verify it fails**

Run:

```bash
swift test --filter DashboardPresentationTests.dashboardCurrencyFormattingUsesTwoDecimals
```

Expected: compilation fails because `MoneyFormatter.dashboardString` does not exist.

- [ ] **Step 3: Add the dashboard formatter without changing precise formatting**

Replace the current `MoneyFormatter` enum with:

```swift
public enum MoneyFormatter {
    public static func string(
        _ money: Money,
        locale: Locale = .current
    ) -> String {
        format(
            money,
            locale: locale,
            minimumFractionDigits: 2,
            maximumFractionDigits: 8
        )
    }

    public static func dashboardString(
        _ money: Money,
        locale: Locale = .current
    ) -> String {
        format(
            money,
            locale: locale,
            minimumFractionDigits: 2,
            maximumFractionDigits: 2
        )
    }

    private static func format(
        _ money: Money,
        locale: Locale,
        minimumFractionDigits: Int,
        maximumFractionDigits: Int
    ) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.locale = locale
        formatter.currencyCode = money.currency
        formatter.minimumFractionDigits = minimumFractionDigits
        formatter.maximumFractionDigits = maximumFractionDigits
        formatter.roundingMode = .halfEven
        formatter.usesGroupingSeparator = true
        return formatter.string(from: NSDecimalNumber(decimal: money.amount))
            ?? "\(money.currency) \(NSDecimalNumber(decimal: money.amount).stringValue)"
    }
}
```

- [ ] **Step 4: Run both currency tests**

Run:

```bash
swift test --filter DashboardPresentationTests
```

Expected: all dashboard presentation tests pass, including the existing full-precision assertion and the new `$423.98` assertion.

- [ ] **Step 5: Commit the formatter change**

```bash
git add Sources/QuotaGlanceCore/Presentation/DashboardPresentation.swift Tests/QuotaGlanceCoreTests/DashboardPresentationTests.swift
git commit -m "feat: add concise dashboard currency formatting"
```

### Task 2: Derive Menu Bar Presentation Data

**Files:**
- Create: `Tests/QuotaGlanceCoreTests/MenuBarPresentationTests.swift`
- Create: `Sources/QuotaGlanceCore/Presentation/MenuBarPresentation.swift`

- [ ] **Step 1: Write failing tests for menu bar derivation**

Create `Tests/QuotaGlanceCoreTests/MenuBarPresentationTests.swift`:

```swift
import Foundation
import Testing
@testable import QuotaGlanceCore

@Suite("Menu bar presentation")
struct MenuBarPresentationTests {
    @Test("Latest seven days are chronological and have bounded labels")
    func latestSevenDaysAreChronological() throws {
        let account = account(
            dailyUsage: [23, 16, 22, 15, 21, 20, 19, 18, 17].map {
                day($0)
            }
        )
        let presentation = try #require(makePresentation(account: account))

        #expect(presentation.days.map(\.date) == [
            "2026-07-17", "2026-07-18", "2026-07-19",
            "2026-07-20", "2026-07-21", "2026-07-22", "2026-07-23"
        ])
        #expect(presentation.days.map(\.label) == [
            "17", "18", "19", "20", "21", "22", "23"
        ])
    }

    @Test("Malformed dates preserve provider order and use bounded labels")
    func malformedDatesPreserveProviderOrder() throws {
        let usage = [
            DailyUsage(date: "bad-date-a", actualCost: usd("1")),
            DailyUsage(date: "bad-date-b", actualCost: usd("2"))
        ]
        let presentation = try #require(
            makePresentation(account: account(dailyUsage: usage))
        )

        #expect(presentation.days.map(\.date) == ["bad-date-a", "bad-date-b"])
        #expect(presentation.days.map(\.label) == ["bad", "bad"])
    }

    @Test("Models are cost-descending, stable for ties, and nil costs are last")
    func modelsAreCostDescending() throws {
        let models = [
            ModelUsage(model: "first-tie", actualCost: usd("10")),
            ModelUsage(model: "missing"),
            ModelUsage(model: "highest", actualCost: usd("12")),
            ModelUsage(model: "second-tie", actualCost: usd("10"))
        ]
        let presentation = try #require(
            makePresentation(account: account(modelUsage: models))
        )

        #expect(presentation.modelRows.map(\.model) == ["highest", "first-tie"])
    }

    @Test(
        "Quota progress handles normal, over-limit, zero-limit, and missing values",
        arguments: [
            (used: "50", limit: "100", fraction: 0.5),
            (used: "125", limit: "100", fraction: 1.0),
            (used: "50", limit: "0", fraction: nil),
            (used: nil, limit: "100", fraction: nil)
        ]
    )
    func quotaProgress(
        used: String?,
        limit: String?,
        fraction: Double?
    ) throws {
        let presentation = try #require(
            makePresentation(
                account: account(
                    quotaUsed: used.map(usd),
                    quotaLimit: limit.map(usd)
                )
            )
        )

        #expect(presentation.quota?.fraction == fraction)
    }

    @Test("All Accounts exposes at most five healthy and unhealthy rows")
    func allAccountsShowsFiveRows() throws {
        let accounts = (0..<6).map { index in
            AccountSnapshot(
                accountID: UUID(),
                displayName: "Account \(index)",
                usage: ProviderUsageSnapshot(
                    remaining: usd("100"),
                    receivedAt: Date(timeIntervalSince1970: 200)
                ),
                health: index == 1 ? .stale(.offline) : .healthy,
                lastSuccessAt: Date(timeIntervalSince1970: 200)
            )
        }
        let envelope = WidgetSnapshotEnvelope(
            capturedAt: Date(timeIntervalSince1970: 200),
            aggregate: AggregateSnapshot(
                remaining: usd("600"),
                accounts: accounts,
                isPartial: true
            ),
            accounts: accounts
        )
        let presentation = try #require(
            MenuBarPresenter.make(selection: .allAccounts, envelope: envelope)
        )

        #expect(presentation.accountRows.count == 5)
        #expect(presentation.accountRows[0].health == .healthy)
        #expect(presentation.accountRows[1].health == .stale(.offline))
        #expect(presentation.status == .partial)
    }
}

private func makePresentation(
    account: AccountSnapshot
) -> MenuBarPresentation? {
    let aggregate = AggregateSnapshot(
        remaining: account.remaining,
        todayActualCost: account.usage?.today?.actualCost,
        todayRequests: account.usage?.today?.requests,
        dailyUsage: account.usage?.dailyUsage ?? [],
        accounts: [account]
    )
    let envelope = WidgetSnapshotEnvelope(
        capturedAt: Date(timeIntervalSince1970: 200),
        aggregate: aggregate,
        accounts: [account]
    )
    return MenuBarPresenter.make(
        selection: .account(account.accountID),
        envelope: envelope
    )
}

private func account(
    quotaUsed: Money? = usd("50"),
    quotaLimit: Money? = usd("100"),
    dailyUsage: [DailyUsage] = [],
    modelUsage: [ModelUsage] = []
) -> AccountSnapshot {
    let receivedAt = Date(timeIntervalSince1970: 200)
    return AccountSnapshot(
        accountID: UUID(),
        displayName: "Primary",
        usage: ProviderUsageSnapshot(
            remaining: usd("50"),
            quotaLimit: quotaLimit,
            quotaUsed: quotaUsed,
            today: UsageCounters(actualCost: usd("2"), requests: 4),
            dailyUsage: dailyUsage,
            modelUsage: modelUsage,
            receivedAt: receivedAt
        ),
        health: .healthy,
        lastSuccessAt: receivedAt
    )
}

private func day(_ value: Int) -> DailyUsage {
    DailyUsage(
        date: String(format: "2026-07-%02d", value),
        actualCost: usd(String(value))
    )
}

private func usd(_ amount: String) -> Money {
    Money(amount: Decimal(string: amount)!, currency: "USD")
}
```

- [ ] **Step 2: Run the new test suite and verify it fails**

Run:

```bash
swift test --filter MenuBarPresentationTests
```

Expected: compilation fails because `MenuBarPresentation` and `MenuBarPresenter` do not exist.

- [ ] **Step 3: Implement the menu-bar-only presenter**

Create `Sources/QuotaGlanceCore/Presentation/MenuBarPresentation.swift`:

```swift
import Foundation

public struct MenuBarDayPresentation: Equatable, Identifiable, Sendable {
    public var id: String { date }
    public let date: String
    public let label: String
    public let actualCost: Money
}

public struct MenuBarQuotaPresentation: Equatable, Sendable {
    public let used: Money?
    public let limit: Money?
    public let fraction: Double?
}

public struct MenuBarPresentation: Equatable, Sendable {
    public let title: String
    public let remaining: Money?
    public let todayActualCost: Money?
    public let todayRequests: Int64?
    public let days: [MenuBarDayPresentation]
    public let accountRows: [AccountSnapshot]
    public let quota: MenuBarQuotaPresentation?
    public let modelRows: [ModelUsage]
    public let status: DashboardStatus
    public let lastSuccessAt: Date?
}

public enum MenuBarPresenter {
    public static func make(
        selection: DashboardSelection,
        envelope: WidgetSnapshotEnvelope
    ) -> MenuBarPresentation? {
        guard let dashboard = DashboardPresenter.make(
            selection: selection,
            envelope: envelope
        ) else {
            return nil
        }

        return MenuBarPresentation(
            title: dashboard.title,
            remaining: dashboard.remaining,
            todayActualCost: dashboard.todayActualCost,
            todayRequests: dashboard.todayRequests,
            days: makeDays(dashboard.dailyUsage),
            accountRows: Array(dashboard.accountRows.prefix(5)),
            quota: makeQuota(dashboard.usage),
            modelRows: makeModelRows(dashboard.usage?.modelUsage ?? []),
            status: dashboard.status,
            lastSuccessAt: dashboard.lastSuccessAt
        )
    }

    private static func makeDays(
        _ dailyUsage: [DailyUsage]
    ) -> [MenuBarDayPresentation] {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.isLenient = false

        let indexed = dailyUsage.enumerated().map { index, usage in
            (index: index, usage: usage, date: formatter.date(from: usage.date))
        }
        let ordered: [DailyUsage]
        if indexed.allSatisfy({ $0.date != nil }) {
            ordered = indexed.sorted { lhs, rhs in
                guard lhs.date != rhs.date else { return lhs.index < rhs.index }
                return lhs.date! < rhs.date!
            }.map(\.usage)
        } else {
            ordered = dailyUsage
        }

        return ordered.suffix(7).map { usage in
            MenuBarDayPresentation(
                date: usage.date,
                label: dayLabel(usage.date, formatter: formatter),
                actualCost: usage.actualCost
            )
        }
    }

    private static func dayLabel(
        _ value: String,
        formatter: DateFormatter
    ) -> String {
        if formatter.date(from: value) != nil,
           let component = value.split(separator: "-").last,
           let day = Int(component) {
            return String(day)
        }
        let fallback = String(value.prefix(3))
        return fallback.isEmpty ? "--" : fallback
    }

    private static func makeQuota(
        _ usage: ProviderUsageSnapshot?
    ) -> MenuBarQuotaPresentation? {
        guard let usage,
              usage.quotaUsed != nil || usage.quotaLimit != nil else {
            return nil
        }

        var fraction: Double?
        if let used = usage.quotaUsed,
           let limit = usage.quotaLimit,
           used.currency == limit.currency,
           limit.amount > 0 {
            let raw = NSDecimalNumber(
                decimal: used.amount / limit.amount
            ).doubleValue
            fraction = min(max(raw, 0), 1)
        }

        return MenuBarQuotaPresentation(
            used: usage.quotaUsed,
            limit: usage.quotaLimit,
            fraction: fraction
        )
    }

    private static func makeModelRows(
        _ models: [ModelUsage]
    ) -> [ModelUsage] {
        models.enumerated().sorted { lhs, rhs in
            switch (lhs.element.actualCost, rhs.element.actualCost) {
            case let (left?, right?) where left.amount != right.amount:
                return left.amount > right.amount
            case (_?, nil):
                return true
            case (nil, _?):
                return false
            default:
                return lhs.offset < rhs.offset
            }
        }
        .prefix(2)
        .map(\.element)
    }
}
```

- [ ] **Step 4: Run the focused tests and fix only contract mismatches**

Run:

```bash
swift test --filter MenuBarPresentationTests
```

Expected: all menu bar presentation tests pass.

- [ ] **Step 5: Run the complete core test suite**

Run:

```bash
swift test
```

Expected: the complete suite passes, including `WidgetPresentationTests`; widget mapping remains on `DashboardPresenter`.

- [ ] **Step 6: Commit the menu bar presentation boundary**

```bash
git add Sources/QuotaGlanceCore/Presentation/MenuBarPresentation.swift Tests/QuotaGlanceCoreTests/MenuBarPresentationTests.swift
git commit -m "feat: derive concise menu bar presentation"
```

### Task 3: Implement the Approved SwiftUI Layout

**Files:**
- Modify: `App/MenuBar/MenuBarDashboardView.swift`
- Modify: `App/MenuBar/UsageChartView.swift`

- [ ] **Step 1: Establish a green baseline before the view edit**

Run:

```bash
swift test
```

Expected: all tests pass.

- [ ] **Step 2: Make the chart consume prepared seven-day rows**

Replace `UsageChartView` with:

```swift
import QuotaGlanceCore
import SwiftUI

struct UsageChartView: View {
    let days: [MenuBarDayPresentation]

    private var maximum: Double {
        max(
            days.map {
                NSDecimalNumber(decimal: $0.actualCost.amount).doubleValue
            }.max() ?? 0,
            0.000_001
        )
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 6) {
            ForEach(Array(days.enumerated()), id: \.element.id) { index, day in
                VStack(spacing: 4) {
                    GeometryReader { proxy in
                        let value = NSDecimalNumber(
                            decimal: day.actualCost.amount
                        ).doubleValue
                        let height = max(2, proxy.size.height * value / maximum)

                        RoundedRectangle(cornerRadius: 2)
                            .fill(
                                index == days.count - 1
                                    ? Color.accentColor
                                    : Color.secondary.opacity(0.28)
                            )
                            .frame(height: height)
                            .frame(maxHeight: .infinity, alignment: .bottom)
                    }
                    .frame(height: 54)

                    Text(day.label)
                        .font(.caption2)
                        .foregroundStyle(
                            index == days.count - 1 ? .primary : .secondary
                        )
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity)
                .help(
                    "\(day.date) - \(MoneyFormatter.dashboardString(day.actualCost))"
                )
            }
        }
        .frame(height: 72)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Seven day usage")
    }
}
```

- [ ] **Step 3: Switch the view to the menu bar presenter and approved hierarchy**

In `MenuBarDashboardView`, change the presentation property to:

```swift
private var presentation: MenuBarPresentation? {
    guard let envelope = model.latestEnvelope else { return nil }
    return MenuBarPresenter.make(selection: selection, envelope: envelope)
}
```

Replace `dashboard(_:)` with:

```swift
private func dashboard(_ presentation: MenuBarPresentation) -> some View {
    VStack(alignment: .leading, spacing: 14) {
        VStack(alignment: .leading, spacing: 3) {
            Text("Remaining")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(
                presentation.remaining.map {
                    MoneyFormatter.dashboardString($0)
                } ?? "--"
            )
            .font(.system(size: 32, weight: .semibold, design: .rounded))
            .lineLimit(1)
            .minimumScaleFactor(0.72)
            .accessibilityLabel("Remaining balance")

            statusLabel(presentation.status)
        }

        if let quota = presentation.quota {
            quotaSection(quota)
        }

        HStack(spacing: 0) {
            metric(
                title: "Today",
                value: presentation.todayActualCost.map {
                    MoneyFormatter.dashboardString($0)
                } ?? "--"
            )
            Divider()
                .frame(height: 34)
                .padding(.horizontal, 12)
            metric(
                title: "Requests",
                value: presentation.todayRequests?.formatted() ?? "--"
            )
        }

        if !presentation.days.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("Last 7 Days")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                UsageChartView(days: presentation.days)
            }
        }

        if case .allAccounts = selection {
            accountSection(presentation.accountRows)
        } else {
            modelSection(presentation.modelRows)
        }

        if let error = model.lastErrorMessage {
            Label(error, systemImage: "exclamationmark.triangle")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
```

- [ ] **Step 4: Add quota, account, and model sections**

Remove `attentionSection(_:)` and `accountDetails(_:)`, then add:

```swift
@ViewBuilder
private func quotaSection(_ quota: MenuBarQuotaPresentation) -> some View {
    VStack(alignment: .leading, spacing: 6) {
        if let fraction = quota.fraction {
            ProgressView(value: fraction)
                .progressViewStyle(.linear)
                .accessibilityLabel("Quota used")
                .accessibilityValue(fraction.formatted(.percent.precision(.fractionLength(0))))
        }

        HStack(spacing: 14) {
            if let used = quota.used {
                metric(
                    title: "Used",
                    value: MoneyFormatter.dashboardString(used)
                )
            }
            if let limit = quota.limit {
                metric(
                    title: "Limit",
                    value: MoneyFormatter.dashboardString(limit)
                )
            }
        }
    }
}

@ViewBuilder
private func accountSection(_ accounts: [AccountSnapshot]) -> some View {
    if !accounts.isEmpty {
        VStack(alignment: .leading, spacing: 7) {
            Text("Accounts")
                .font(.caption)
                .foregroundStyle(.secondary)
            ForEach(accounts) { account in
                HStack(spacing: 7) {
                    Circle()
                        .fill(
                            color(
                                for: DashboardPresenterStatus.health(
                                    account.health
                                )
                            )
                        )
                        .frame(width: 7, height: 7)
                    Text(account.displayName)
                        .lineLimit(1)
                    Spacer()
                    Text(
                        account.remaining.map {
                            MoneyFormatter.dashboardString($0)
                        } ?? "--"
                    )
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                }
                .font(.caption)
            }
        }
    }
}

@ViewBuilder
private func modelSection(_ models: [ModelUsage]) -> some View {
    if !models.isEmpty {
        VStack(alignment: .leading, spacing: 6) {
            Text("Top Models")
                .font(.caption)
                .foregroundStyle(.secondary)
            ForEach(models) { model in
                HStack {
                    Text(model.model)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    Text(
                        model.actualCost.map {
                            MoneyFormatter.dashboardString($0)
                        } ?? "--"
                    )
                    .foregroundStyle(.secondary)
                }
                .font(.caption)
            }
        }
    }
}
```

- [ ] **Step 5: Move freshness into the footer and retain Quit**

Replace `footer` with:

```swift
private var footer: some View {
    HStack(spacing: 10) {
        SettingsLink {
            Label("Settings", systemImage: "gearshape")
        }
        Spacer(minLength: 6)
        if let lastSuccessAt = presentation?.lastSuccessAt {
            HStack(spacing: 4) {
                Image(systemName: "clock")
                Text(lastSuccessAt, style: .relative)
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
        Spacer(minLength: 6)
        Button("Quit") {
            NSApplication.shared.terminate(nil)
        }
        .buttonStyle(.borderless)
    }
}
```

Delete the old last-success row from `dashboard(_:)`. Ensure every menu bar currency call now uses `MoneyFormatter.dashboardString`; leave notifications and widgets on `MoneyFormatter.string`.

- [ ] **Step 6: Compile the app and widget with the local toolchain**

Run:

```bash
./scripts/build-local.sh Debug
```

Expected: exit status 0, an ad-hoc signed `QuotaGlance.app` path under `DerivedData/ManualBuild/Debug.*`, and no Swift compiler errors.

- [ ] **Step 7: Run all core tests again**

Run:

```bash
swift test
```

Expected: all tests pass.

- [ ] **Step 8: Commit the SwiftUI layout**

```bash
git add App/MenuBar/MenuBarDashboardView.swift App/MenuBar/UsageChartView.swift
git commit -m "feat: polish menu bar usage dashboard"
```

### Task 4: Install And Verify The Live App

**Files:**
- Verify: `~/Applications/QuotaGlance.app`
- Verify: `~/Library/Group Containers/group.com.liangrui.QuotaGlance/quota-snapshot-v1.json`

- [ ] **Step 1: Run the complete automated suite from a clean code state**

Run:

```bash
swift test
```

Expected: all tests pass with no failures.

- [ ] **Step 2: Install the release build and relaunch the app**

Run:

```bash
./scripts/install-local.sh
```

Expected: the previous app is moved to `~/Library/Application Support/QuotaGlance/Backups`, the new app is installed at `~/Applications/QuotaGlance.app`, the widget is registered, and the process launches.

- [ ] **Step 3: Verify the process, bundle identifiers, and widget registration**

Run:

```bash
pgrep -x QuotaGlance
/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$HOME/Applications/QuotaGlance.app/Contents/Info.plist"
/usr/bin/pluginkit -m -A -D
```

Expected: `pgrep` prints a PID, the app bundle identifier is `com.liangrui.QuotaGlance`, and PlugInKit includes `com.liangrui.QuotaGlance.Widget`.

- [ ] **Step 4: Verify no configured API key bytes entered tracked files or the installed bundle**

Run:

```bash
./scripts/verify-no-secret.sh
```

Expected: `No configured API key bytes found`.

- [ ] **Step 5: Inspect the installed menu bar panel with live data**

Open the menu bar panel and verify all of the following against a screenshot:

- remaining, today, used, limit, model, and account amounts show two decimals;
- the quota progress bar appears between status and today metrics;
- the chart has no more than seven bars with non-overlapping day labels;
- a selected account shows at most two top model rows;
- All Accounts shows healthy and unhealthy account rows, up to five;
- Settings, relative freshness, and Quit fit in the footer;
- refresh remains usable and updates the values without resizing the panel;
- stale or provider errors remain readable beneath the content.

- [ ] **Step 6: Confirm repository state**

Run:

```bash
git status --short
git log --oneline -4
```

Expected: no uncommitted tracked changes; the design, formatter, presentation, and SwiftUI commits are the newest relevant commits.
