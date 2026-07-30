import AppKit
import QuotaGlanceCore
import SwiftUI

struct MenuBarDashboardView: View {
    @ObservedObject var model: AppModel
    let openSettings: () -> Void

    init(
        model: AppModel,
        openSettings: @escaping () -> Void = {}
    ) {
        self.model = model
        self.openSettings = openSettings
    }

    private var selection: DashboardSelection {
        model.selectedAccountID.map(DashboardSelection.account) ?? .allAccounts
    }

    private var presentation: MenuBarPresentation? {
        guard let envelope = model.latestEnvelope else { return nil }
        return MenuBarPresenter.make(selection: selection, envelope: envelope)
    }

    private var panelSize: MenuBarPanelSize {
        MenuBarPanelLayout.fixedContentSize
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.horizontal, 14)
                .padding(.vertical, 12)

            Divider()

            Group {
                if model.accounts.isEmpty {
                    emptyState
                } else if let presentation {
                    ScrollView {
                        dashboard(presentation)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                } else {
                    unavailableState
                }
            }
            .frame(
                maxWidth: .infinity,
                maxHeight: .infinity,
                alignment: .topLeading
            )
            .padding(14)

            Divider()

            footer
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
        }
        .frame(
            width: CGFloat(panelSize.width),
            height: CGFloat(panelSize.height),
            alignment: .topLeading
        )
        .onOpenURL { url in
            model.handle(url: url)
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Picker(
                "Account",
                selection: Binding(
                    get: { model.selectedAccountID },
                    set: { model.selectedAccountID = $0 }
                )
            ) {
                Text("All Accounts").tag(nil as UUID?)
                ForEach(model.accounts) { account in
                    Text(account.displayName)
                        .lineLimit(1)
                        .tag(account.id as UUID?)
                }
            }
            .labelsHidden()
            .frame(maxWidth: .infinity, alignment: .leading)

            if model.isRefreshing {
                ProgressView()
                    .controlSize(.small)
                    .frame(width: 28, height: 28)
            } else {
                Button {
                    Task { await model.refresh() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .foregroundStyle(.primary)
                }
                .buttonStyle(.borderless)
                .frame(width: 28, height: 28)
                .disabled(model.accounts.isEmpty)
                .help("Refresh")
            }
        }
    }

    private func dashboard(_ presentation: MenuBarPresentation) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            primarySection(presentation)

            if case .allAccounts = selection {
                activitySection(presentation)
            } else {
                balanceSection(presentation.balanceRows)

                if let spendingLimit = presentation.spendingLimit {
                    spendingLimitSection(spendingLimit)
                }

                if !presentation.spend.isEmpty {
                    spendSection(presentation.spend)
                }

                quotaWindowSection(presentation.quotaWindows)

                if let requests = presentation.todayRequests {
                    metric(title: "Requests today", value: requests.formatted())
                }
            }

            if !presentation.days.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    sectionHeader("Last 7 Days")
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

    @ViewBuilder
    private func primarySection(_ presentation: MenuBarPresentation) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            if case .allAccounts = selection {
                sectionHeader("Balances")
                if presentation.balances.isEmpty {
                    if let reason = presentation.metricsUnavailableReason {
                        connectionOnlyMetric(reason)
                    } else {
                        Text("--")
                            .font(.system(size: 30, weight: .semibold, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                } else {
                    ForEach(presentation.balances, id: \.currency) { balance in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(MoneyFormatter.dashboardString(balance))
                                .font(
                                    .system(
                                        size: presentation.balances.count == 1 ? 30 : 22,
                                        weight: .semibold,
                                        design: .rounded
                                    )
                                )
                                .lineLimit(1)
                                .minimumScaleFactor(0.72)
                            Spacer(minLength: 6)
                            Text(balance.currency)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            } else if let metric = presentation.primaryMetric {
                Text(metric.label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(PrimaryMetricFormatter.string(metric.value))
                    .font(.system(size: 30, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
            } else if let reason = presentation.metricsUnavailableReason {
                connectionOnlyMetric(reason)
            } else {
                Text("No metric")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("--")
                    .font(.system(size: 30, weight: .semibold, design: .rounded))
            }

            statusLabel(presentation.status)
        }
    }

    private func connectionOnlyMetric(_ reason: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("Connected")
                .font(.system(size: 24, weight: .semibold, design: .rounded))
            Text(reason)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private func activitySection(_ presentation: MenuBarPresentation) -> some View {
        if presentation.todayActualCost != nil || presentation.todayRequests != nil {
            HStack(spacing: 0) {
                metric(
                    title: "Spent today",
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
        }
    }

    private func metric(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func balanceSection(_ balances: [MonetaryBalance]) -> some View {
        if !balances.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                sectionHeader("Balances")
                ForEach(balances) { balance in
                    VStack(alignment: .leading, spacing: 5) {
                        valueRow(
                            balance.label,
                            value: MoneyFormatter.dashboardString(balance.available),
                            emphasized: true
                        )
                        ForEach(balance.breakdown) { item in
                            valueRow(
                                item.label,
                                value: MoneyFormatter.dashboardString(item.value)
                            )
                            .padding(.leading, 10)
                        }
                    }
                }
            }
        }
    }

    private func spendingLimitSection(_ limit: SpendingLimit) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader(limit.label)
            if let fraction = moneyProgressFraction(limit) {
                ProgressView(value: fraction)
                    .progressViewStyle(.linear)
                    .accessibilityLabel(limit.label)
                    .accessibilityValue(
                        fraction.formatted(.percent.precision(.fractionLength(0)))
                    )
            }
            HStack(spacing: 12) {
                if let remaining = limit.remaining {
                    metric(
                        title: "Remaining",
                        value: MoneyFormatter.dashboardString(remaining)
                    )
                }
                if let used = limit.used {
                    metric(title: "Used", value: MoneyFormatter.dashboardString(used))
                }
                if let total = limit.limit {
                    metric(title: "Limit", value: MoneyFormatter.dashboardString(total))
                }
            }
            if let resetDescription = limit.resetDescription {
                Text(resetDescription)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func spendSection(_ spend: SpendSummary) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionHeader("Spend")
            if let today = spend.today {
                valueRow("Today", value: MoneyFormatter.dashboardString(today))
            }
            if let week = spend.week {
                valueRow("This week", value: MoneyFormatter.dashboardString(week))
            }
            if let month = spend.month {
                valueRow("This month", value: MoneyFormatter.dashboardString(month))
            }
            if let total = spend.total {
                valueRow("Total", value: MoneyFormatter.dashboardString(total))
            }
        }
    }

    @ViewBuilder
    private func quotaWindowSection(_ windows: [QuotaWindow]) -> some View {
        if !windows.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                sectionHeader("Quota Windows")
                ForEach(windows) { window in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(window.label)
                            .font(.caption)
                            .fontWeight(.medium)
                        if let fraction = progressFraction(
                            used: window.used,
                            limit: window.limit
                        ) {
                            ProgressView(value: fraction)
                                .progressViewStyle(.linear)
                                .accessibilityLabel(window.label)
                                .accessibilityValue(
                                    fraction.formatted(
                                        .percent.precision(.fractionLength(0))
                                    )
                                )
                        }
                        HStack(spacing: 12) {
                            if let remaining = window.remaining {
                                metric(
                                    title: "Remaining",
                                    value: quantity(remaining, unit: window.unit)
                                )
                            }
                            if let used = window.used {
                                metric(
                                    title: "Used",
                                    value: quantity(used, unit: window.unit)
                                )
                            }
                            if let limit = window.limit {
                                metric(
                                    title: "Limit",
                                    value: quantity(limit, unit: window.unit)
                                )
                            }
                        }
                        if let resetsAt = window.resetsAt {
                            Text("Resets \(resetsAt, style: .relative)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    private func valueRow(
        _ title: String,
        value: String,
        emphasized: Bool = false
    ) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title)
                .lineLimit(1)
            Spacer(minLength: 8)
            Text(value)
                .fontWeight(emphasized ? .medium : .regular)
                .foregroundStyle(emphasized ? .primary : .secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .font(.caption)
    }

    private func quantity(_ value: Decimal, unit: String) -> String {
        PrimaryMetricFormatter.string(.quantity(value, unit: unit))
    }

    private func moneyProgressFraction(_ limit: SpendingLimit) -> Double? {
        guard let used = limit.used,
              let total = limit.limit,
              used.currency == total.currency else {
            return nil
        }
        return progressFraction(used: used.amount, limit: total.amount)
    }

    private func progressFraction(
        used: Decimal?,
        limit: Decimal?
    ) -> Double? {
        guard let used, let limit, limit > 0 else { return nil }
        let fraction = NSDecimalNumber(decimal: used / limit).doubleValue
        return min(max(fraction, 0), 1)
    }

    @ViewBuilder
    private func accountSection(_ accounts: [CompactAccountPresentation]) -> some View {
        if !accounts.isEmpty {
            VStack(alignment: .leading, spacing: 7) {
                sectionHeader("Accounts")
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
                        if let metric = account.primaryMetric {
                            VStack(alignment: .trailing, spacing: 1) {
                                Text(PrimaryMetricFormatter.string(metric.value))
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.75)
                                Text(metric.label)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        } else if account.metricsUnavailableReason != nil {
                            Text("Connected")
                                .foregroundStyle(.secondary)
                        } else {
                            Text("--")
                                .foregroundStyle(.secondary)
                        }
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
                sectionHeader("Top Models")
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

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(compatibleSystemName: CompatibleSystemSymbol.emptyState)
                .font(.system(size: 30))
                .foregroundStyle(.secondary)
            Text("No Accounts")
                .font(.headline)
            Button(action: openSettings) {
                Label("Add Account", systemImage: "plus")
            }
        }
        .frame(maxWidth: .infinity, minHeight: 180)
    }

    private var unavailableState: some View {
        VStack(spacing: 12) {
            if model.isRefreshing {
                ProgressView()
            } else {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 28))
                    .foregroundStyle(.secondary)
                Text(model.lastErrorMessage ?? "No Data")
                    .multilineTextAlignment(.center)
                Button {
                    Task { await model.refresh() }
                } label: {
                    Label("Retry", systemImage: "arrow.clockwise")
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: 180)
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Button(action: openSettings) {
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

    private func statusLabel(_ status: DashboardStatus) -> some View {
        let detail = DashboardPresenterStatus.detail(status)
        return Label(detail.text, systemImage: detail.icon)
            .font(.caption)
            .foregroundStyle(detail.color)
    }

    private func color(for status: DashboardStatus) -> Color {
        DashboardPresenterStatus.detail(status).color
    }
}

private enum DashboardPresenterStatus {
    struct Detail {
        let text: String
        let icon: String
        let color: Color
    }

    static func health(_ health: AccountHealth) -> DashboardStatus {
        switch health {
        case .healthy: .healthy
        case .belowThreshold: .belowThreshold
        case let .stale(failure): .stale(failure)
        case let .unavailable(failure): .unavailable(failure)
        }
    }

    static func detail(_ status: DashboardStatus) -> Detail {
        switch status {
        case .healthy:
            Detail(text: "Up to Date", icon: "checkmark.circle.fill", color: .green)
        case .belowThreshold:
            Detail(text: "Low Balance", icon: "exclamationmark.circle.fill", color: .orange)
        case .partial:
            Detail(text: "Partial Data", icon: "exclamationmark.triangle.fill", color: .orange)
        case .stale(.keychainAccessRequired), .unavailable(.keychainAccessRequired):
            Detail(text: "Keychain Locked", icon: "lock.fill", color: .orange)
        case .stale:
            Detail(text: "Saved Data", icon: "clock.badge.exclamationmark", color: .orange)
        case .unavailable:
            Detail(text: "Unavailable", icon: "xmark.circle.fill", color: .red)
        case .empty:
            Detail(text: "No Data", icon: "minus.circle", color: .secondary)
        }
    }
}
