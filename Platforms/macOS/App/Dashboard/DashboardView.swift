import AppKit
import QuotaGlanceCore
import SwiftUI

struct DashboardView: View {
    @ObservedObject var model: AppModel

    private var language: AppLanguage { model.resolvedLanguage }
    private var selection: DashboardSelection {
        model.selectedAccountID.map(DashboardSelection.account) ?? .allAccounts
    }
    private var presentation: DashboardPresentation {
        DashboardPresenter.make(
            selection: selection,
            accounts: model.accounts,
            envelope: model.latestEnvelope,
            language: language
        )
    }
    private var allAccountsPresentation: DashboardPresentation {
        DashboardPresenter.make(
            selection: .allAccounts,
            accounts: model.accounts,
            envelope: model.latestEnvelope,
            language: language
        )
    }
    private var chartDays: [MenuBarDayPresentation] {
        guard let envelope = model.latestEnvelope else { return [] }
        return MenuBarPresenter.make(
            selection: selection,
            envelope: envelope,
            language: language
        )?.days ?? []
    }

    var body: some View {
        NavigationView {
            sidebar
                .frame(minWidth: 230, idealWidth: 250, maxWidth: 280)
            detail
                .frame(minWidth: 620, maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationViewStyle(DoubleColumnNavigationViewStyle())
        .frame(minWidth: 960, minHeight: 620)
        .environment(\.locale, language.locale)
        .preferredColorScheme(model.preferences.preferredTheme.colorScheme)
        .id(language)
        .background(
            DashboardWindowTitleUpdater(
                title: L10n.string(.dashboardWindowTitle, language: language)
            )
        )
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("QuotaGlance")
                .font(.headline)
                .padding(.horizontal, 14)
                .padding(.vertical, 15)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    sidebarButton(
                        title: L10n.string(.allAccounts, language: language),
                        subtitle: accountCountText(model.accounts.count),
                        metric: nil,
                        status: allAccountsPresentation.status,
                        isDisabled: false,
                        selection: .allAccounts
                    )
                    ForEach(model.accounts) { account in
                        let snapshot = model.latestEnvelope?.accounts.first {
                            $0.accountID == account.id
                        }
                        sidebarButton(
                            title: account.displayName,
                            subtitle: ProviderCatalog.descriptor(
                                for: account.provider
                            ).displayName,
                            metric: DashboardPresenter.primaryMetric(
                                for: snapshot?.usage,
                                language: language
                            ),
                            status: snapshot.map { dashboardStatus($0.health) } ?? .empty,
                            isDisabled: !account.isEnabled,
                            selection: .account(account.id)
                        )
                    }
                }
                .padding(8)
            }
            sidebarFooter
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private var sidebarFooter: some View {
        VStack(alignment: .leading, spacing: 4) {
            Divider()

            Button {
                model.isShowingSettings = true
            } label: {
                Label(
                    L10n.string(.settings, language: language),
                    systemImage: "gearshape"
                )
                .font(.body.weight(model.isShowingSettings ? .semibold : .regular))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10)
                .padding(.vertical, 9)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(
                            model.isShowingSettings
                                ? Color.accentColor.opacity(0.16)
                                : .clear
                        )
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Menu {
                ForEach(AppThemePreference.allCases) { theme in
                    Button {
                        model.setPreferredTheme(theme)
                    } label: {
                        if model.preferences.preferredTheme == theme {
                            Label(
                                L10n.themePreferenceTitle(theme, language: language),
                                systemImage: "checkmark"
                            )
                        } else {
                            Text(L10n.themePreferenceTitle(theme, language: language))
                        }
                    }
                }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "circle.lefthalf.filled")
                        .frame(width: 18)
                    Text(L10n.string(.appearance, language: language))
                        .font(.body)
                    Spacer(minLength: 8)
                    Text(
                        L10n.themePreferenceTitle(
                            model.preferences.preferredTheme,
                            language: language
                        )
                    )
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 9)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
        }
        .padding(8)
    }

    private func sidebarButton(
        title: String,
        subtitle: String,
        metric: PrimaryMetric?,
        status: DashboardStatus,
        isDisabled: Bool,
        selection target: DashboardSelection
    ) -> some View {
        let isSelected = selection == target
        return Button {
            model.selectDashboard(target)
        } label: {
            HStack(spacing: 10) {
                Circle()
                    .fill(isDisabled ? Color.secondary.opacity(0.45) : statusColor(status))
                    .frame(width: 8, height: 8)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.body.weight(isSelected ? .semibold : .regular))
                        .lineLimit(1)
                    HStack(spacing: 5) {
                        Text(isDisabled
                            ? L10n.string(.disabled, language: language)
                            : subtitle)
                        if let metric = metric, !isDisabled {
                            Text("·")
                            Text(PrimaryMetricFormatter.string(metric.value))
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isSelected ? Color.accentColor.opacity(0.16) : .clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(isDisabled ? 0.7 : 1)
    }

    private var detail: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            if model.isShowingSettings {
                SettingsView(model: model, isEmbedded: true)
            } else if model.accounts.isEmpty {
                emptyState
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        if case .allAccounts = selection {
                            allAccountsContent
                        } else {
                            accountContent
                        }
                        if let error = model.lastErrorMessage {
                            Label(error, systemImage: "exclamationmark.triangle.fill")
                                .font(.callout)
                                .foregroundStyle(.orange)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(24)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .background(Color(nsColor: .windowBackgroundColor))
            }
        }
    }

    private var toolbar: some View {
        HStack(spacing: 12) {
            if model.isShowingSettings {
                Text(L10n.string(.settings, language: language))
                    .font(.title2.weight(.semibold))
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    Text(presentation.title)
                        .font(.title2.weight(.semibold))
                        .lineLimit(1)
                    statusLabel(presentation.status)
                }
            }
            Spacer()
            if !model.isShowingSettings {
                if model.isRefreshing {
                    ProgressView()
                        .controlSize(.small)
                        .frame(width: 28, height: 28)
                } else {
                    toolbarButton(
                        systemName: "arrow.clockwise",
                        help: L10n.string(.refresh, language: language)
                    ) {
                        Task { await model.refresh() }
                    }
                    .disabled(model.accounts.isEmpty)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func toolbarButton(
        systemName: String,
        help: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .frame(width: 28, height: 28)
        }
        .buttonStyle(.borderless)
        .help(help)
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(compatibleSystemName: CompatibleSystemSymbol.emptyState)
                .font(.system(size: 36))
                .foregroundStyle(.secondary)
            Text(L10n.string(.noAccounts, language: language))
                .font(.title3.weight(.semibold))
            Text(L10n.string(.addProviderAccountHint, language: language))
                .foregroundStyle(.secondary)
            Button {
                model.isShowingSettings = true
            } label: {
                Label(L10n.string(.addAccount, language: language), systemImage: "plus")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var allAccountsContent: some View {
        VStack(alignment: .leading, spacing: 24) {
            if let serviceStatus = model.openAIServiceStatus {
                openAIServiceStatus(serviceStatus)
            }
            summaryTiles
            if !chartDays.isEmpty {
                dashboardSection(L10n.string(.last7Days, language: language)) {
                    UsageChartView(days: chartDays, language: language)
                        .frame(maxWidth: 620)
                }
            }
            if let overview = presentation.providerOverview {
                providerOverview(overview)
            }
        }
    }

    private func openAIServiceStatus(_ status: OpenAIServiceStatus) -> some View {
        dashboardSection("OpenAI service status") {
            HStack(alignment: .top, spacing: 10) {
                Circle()
                    .fill(serviceStatusColor(status.overall))
                    .frame(width: 9, height: 9)
                    .padding(.top, 5)
                VStack(alignment: .leading, spacing: 4) {
                    Text(status.summary).font(.body.weight(.medium))
                    if !status.affectedComponents.isEmpty {
                        Text(status.affectedComponents.map(\.name).joined(separator: ", "))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    ForEach(status.activeIncidents) { incident in
                        if let url = incident.url {
                            Link(incident.title, destination: url).font(.caption)
                        } else {
                            Text(incident.title).font(.caption)
                        }
                    }
                }
                Spacer(minLength: 0)
                Link("status.openai.com", destination: URL(string: "https://status.openai.com/")!)
                    .font(.caption)
            }
        }
    }

    private func serviceStatusColor(_ level: ServiceStatusLevel) -> Color {
        switch level {
        case .operational: .green
        case .degraded: .orange
        case .outage: .red
        case .unknown: .secondary
        }
    }

    private var summaryTiles: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 170), spacing: 12)],
            spacing: 12
        ) {
            if presentation.balances.isEmpty {
                summaryTile(
                    title: L10n.string(.balances, language: language),
                    value: "--"
                )
            } else {
                ForEach(presentation.balances, id: \.currency) { balance in
                    summaryTile(
                        title: L10n.string(
                            .currencyBalance,
                            language: language,
                            balance.currency
                        ),
                        value: MoneyFormatter.dashboardString(balance)
                    )
                }
            }
            summaryTile(
                title: L10n.string(.spentToday, language: language),
                value: presentation.todayActualCost.map {
                    MoneyFormatter.dashboardString($0)
                } ?? "--"
            )
            summaryTile(
                title: L10n.string(.requestsToday, language: language),
                value: presentation.todayRequests?.formatted() ?? "--"
            )
        }
    }

    private func summaryTile(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 22, weight: .semibold, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 78, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
    }

    private func providerOverview(
        _ overview: ProviderOverviewPresentation
    ) -> some View {
        dashboardSection(L10n.string(.providerOverview, language: language)) {
            VStack(spacing: 0) {
                ForEach(Array(overview.rows.enumerated()), id: \.element.id) {
                    index, row in
                    if index > 0 { Divider() }
                    providerRow(row)
                }
            }
        }
    }

    private func providerRow(_ row: ProviderOverviewRow) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Circle()
                .fill(providerStatusColor(row.status))
                .frame(width: 9, height: 9)
                .padding(.top, 5)
            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline) {
                    Text(row.displayName)
                        .font(.body.weight(.medium))
                    Text(row.accountCountText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(providerStatusTitle(row.status))
                        .font(.caption)
                        .foregroundStyle(providerStatusColor(row.status))
                }
                HStack(spacing: 14) {
                    ForEach(row.balances, id: \.currency) { balance in
                        overviewMetric(
                            L10n.string(.balance, language: language),
                            MoneyFormatter.dashboardString(balance)
                        )
                    }
                    ForEach(row.todayActualCosts, id: \.currency) { cost in
                        overviewMetric(
                            L10n.string(.spentToday, language: language),
                            MoneyFormatter.dashboardString(cost)
                        )
                    }
                    if let metric = row.primaryMetric {
                        overviewMetric(
                            metric.label,
                            PrimaryMetricFormatter.string(metric.value)
                        )
                    }
                    if let requests = row.todayRequests {
                        overviewMetric(
                            L10n.string(.requests, language: language),
                            requests.formatted()
                        )
                    }
                    if let share = row.requestShare {
                        overviewMetric(
                            L10n.string(.requestShare, language: language),
                            PrimaryMetricFormatter.string(
                                .quantity(share * 100, unit: "%")
                            )
                        )
                    }
                }
            }
        }
        .padding(.vertical, 11)
    }

    private func overviewMetric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.body.weight(.medium))
                .lineLimit(1)
        }
    }

    private var accountContent: some View {
        VStack(alignment: .leading, spacing: 24) {
            if let usage = presentation.usage {
                balanceDetails(usage.balances)
                if !chartDays.isEmpty {
                    dashboardSection(L10n.string(.last7Days, language: language)) {
                        UsageChartView(days: chartDays, language: language)
                            .frame(maxWidth: 620)
                    }
                }
                if let limit = usage.spendingLimit { spendingLimitDetails(limit) }
                if !usage.spend.isEmpty { spendDetails(usage.spend) }
                quotaDetails(usage.quotaWindows)
                if let today = usage.today {
                    counterDetails(
                        title: L10n.string(.todayMetrics, language: language),
                        counters: today
                    )
                }
                if let total = usage.total {
                    counterDetails(
                        title: L10n.string(.totalMetrics, language: language),
                        counters: total
                    )
                }
                modelDetails(presentation.modelRows)
                providerDetails(usage)
            } else {
                Text(L10n.string(.noData, language: language))
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            if let lastSuccessAt = presentation.lastSuccessAt {
                HStack(spacing: 6) {
                    Text(L10n.string(.lastSuccessfulRefresh, language: language))
                    Text(lastSuccessAt, style: .relative)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func balanceDetails(_ balances: [MonetaryBalance]) -> some View {
        if !balances.isEmpty {
            dashboardSection(L10n.string(.balances, language: language)) {
                VStack(spacing: 8) {
                    ForEach(balances) { balance in
                        valueRow(balance.label, MoneyFormatter.string(balance.available), emphasized: true)
                        ForEach(balance.breakdown) { item in
                            valueRow(item.label, MoneyFormatter.string(item.value))
                                .padding(.leading, 16)
                        }
                    }
                }
            }
        }
    }

    private func spendingLimitDetails(_ limit: SpendingLimit) -> some View {
        dashboardSection(limit.label) {
            VStack(alignment: .leading, spacing: 8) {
                if let fraction = moneyProgress(limit) {
                    ProgressView(value: fraction)
                        .progressViewStyle(.linear)
                        .frame(maxWidth: 520)
                }
                moneyValues([
                    (L10n.string(.remaining, language: language), limit.remaining),
                    (L10n.string(.used, language: language), limit.used),
                    (L10n.string(.limit, language: language), limit.limit),
                ])
                if let reset = limit.resetDescription {
                    Text(reset).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func spendDetails(_ spend: SpendSummary) -> some View {
        dashboardSection(L10n.string(.spend, language: language)) {
            moneyValues([
                (L10n.string(.today, language: language), spend.today),
                (L10n.string(.thisWeek, language: language), spend.week),
                (L10n.string(.thisMonth, language: language), spend.month),
                (L10n.string(.total, language: language), spend.total),
            ])
        }
    }

    @ViewBuilder
    private func quotaDetails(_ windows: [QuotaWindow]) -> some View {
        if !windows.isEmpty {
            dashboardSection(L10n.string(.quotaWindows, language: language)) {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(windows) { window in
                        VStack(alignment: .leading, spacing: 7) {
                            Text(window.label).font(.body.weight(.medium))
                            if let fraction = progress(window.used, window.limit) {
                                ProgressView(value: fraction)
                                    .progressViewStyle(.linear)
                                    .frame(maxWidth: 520)
                            }
                            HStack(spacing: 20) {
                                decimalMetric(.remaining, window.remaining, unit: window.unit)
                                decimalMetric(.used, window.used, unit: window.unit)
                                decimalMetric(.limit, window.limit, unit: window.unit)
                            }
                            if let resetsAt = window.resetsAt {
                                Text(resetsAt, style: .relative)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
    }

    private func counterDetails(title: String, counters: UsageCounters) -> some View {
        dashboardSection(title) {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 150), spacing: 14)],
                alignment: .leading,
                spacing: 10
            ) {
                if let cost = counters.actualCost {
                    overviewMetric(
                        L10n.string(.spend, language: language),
                        MoneyFormatter.string(cost)
                    )
                }
                integerMetric(.requests, counters.requests)
                integerMetric(.inputTokens, counters.inputTokens)
                integerMetric(.outputTokens, counters.outputTokens)
                integerMetric(.cacheReadTokens, counters.cacheReadTokens)
                integerMetric(.cacheCreationTokens, counters.cacheCreationTokens)
                integerMetric(.totalTokens, counters.totalTokens)
            }
        }
    }

    @ViewBuilder
    private func modelDetails(_ models: [ModelUsage]) -> some View {
        if !models.isEmpty {
            dashboardSection(L10n.string(.modelUsage, language: language)) {
                VStack(spacing: 0) {
                    ForEach(Array(models.enumerated()), id: \.element.id) { index, model in
                        if index > 0 { Divider() }
                        HStack {
                            Text(model.model).lineLimit(1).truncationMode(.middle)
                            Spacer()
                            if let cost = model.actualCost {
                                Text(MoneyFormatter.string(cost))
                            }
                            if let requests = model.requests {
                                Text(requests.formatted())
                            }
                            if let tokens = model.totalTokens {
                                Text(tokens.formatted())
                            }
                        }
                        .font(.body)
                        .padding(.vertical, 10)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func providerDetails(_ usage: ProviderUsageSnapshot) -> some View {
        if usage.providerStatus != nil || usage.metricsUnavailableReason != nil {
            dashboardSection(L10n.string(.status, language: language)) {
                VStack(spacing: 8) {
                    if let status = usage.providerStatus {
                        valueRow(L10n.string(.providerStatus, language: language), status)
                    }
                    if let reason = usage.metricsUnavailableReason {
                        valueRow(L10n.string(.metricsUnavailable, language: language), reason)
                    }
                }
            }
        }
    }

    private func dashboardSection<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.title3.weight(.semibold))
            content()
            Divider()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func valueRow(
        _ title: String,
        _ value: String,
        emphasized: Bool = false
    ) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
            Spacer(minLength: 18)
            Text(value)
                .fontWeight(emphasized ? .semibold : .regular)
                .foregroundStyle(emphasized ? .primary : .secondary)
                .multilineTextAlignment(.trailing)
        }
        .font(.body)
    }

    private func moneyValues(_ values: [(String, Money?)]) -> some View {
        HStack(spacing: 24) {
            ForEach(Array(values.enumerated()), id: \.offset) { _, item in
                if let money = item.1 {
                    overviewMetric(item.0, MoneyFormatter.string(money))
                }
            }
        }
    }

    @ViewBuilder
    private func decimalMetric(_ key: L10nKey, _ value: Decimal?, unit: String) -> some View {
        if let value = value {
            overviewMetric(
                L10n.string(key, language: language),
                PrimaryMetricFormatter.string(.quantity(value, unit: unit))
            )
        }
    }

    @ViewBuilder
    private func integerMetric(_ key: L10nKey, _ value: Int64?) -> some View {
        if let value = value {
            overviewMetric(L10n.string(key, language: language), value.formatted())
        }
    }

    private func statusLabel(_ status: DashboardStatus) -> some View {
        Label(statusTitle(status), systemImage: statusIcon(status))
            .font(.caption)
            .foregroundStyle(statusColor(status))
    }

    private func statusTitle(_ status: DashboardStatus) -> String {
        switch status {
        case .healthy: L10n.string(.upToDate, language: language)
        case .belowThreshold: L10n.string(.lowBalance, language: language)
        case .partial: L10n.string(.partialData, language: language)
        case .stale(.keychainAccessRequired), .unavailable(.keychainAccessRequired):
            L10n.string(.keychainLocked, language: language)
        case .stale: L10n.string(.savedData, language: language)
        case .unavailable: L10n.string(.unavailable, language: language)
        case .empty: L10n.string(.noData, language: language)
        }
    }

    private func statusIcon(_ status: DashboardStatus) -> String {
        switch status {
        case .healthy: "checkmark.circle.fill"
        case .belowThreshold: "exclamationmark.circle.fill"
        case .partial: "exclamationmark.triangle.fill"
        case .stale: "clock.badge.exclamationmark"
        case .unavailable: "xmark.circle.fill"
        case .empty: "minus.circle"
        }
    }

    private func statusColor(_ status: DashboardStatus) -> Color {
        switch status {
        case .healthy: .green
        case .belowThreshold, .partial, .stale: .orange
        case .unavailable: .red
        case .empty: .secondary
        }
    }

    private func providerStatusTitle(_ status: ProviderOverviewStatus) -> String {
        switch status {
        case .disabled: L10n.string(.disabled, language: language)
        case .unavailable: L10n.string(.unavailable, language: language)
        case .partial: L10n.string(.partialData, language: language)
        case .belowThreshold: L10n.string(.lowBalance, language: language)
        case .healthy: L10n.string(.healthy, language: language)
        }
    }

    private func providerStatusColor(_ status: ProviderOverviewStatus) -> Color {
        switch status {
        case .disabled: .secondary
        case .unavailable: .red
        case .partial, .belowThreshold: .orange
        case .healthy: .green
        }
    }

    private func dashboardStatus(_ health: AccountHealth) -> DashboardStatus {
        switch health {
        case .healthy: .healthy
        case .belowThreshold: .belowThreshold
        case let .stale(failure): .stale(failure)
        case let .unavailable(failure): .unavailable(failure)
        }
    }

    private func accountCountText(_ count: Int) -> String {
        count == 1
            ? L10n.string(.oneAccount, language: language)
            : L10n.string(.accountCount, language: language, count)
    }

    private func moneyProgress(_ limit: SpendingLimit) -> Double? {
        guard let used = limit.used,
              let total = limit.limit,
              used.currency == total.currency else { return nil }
        return progress(used.amount, total.amount)
    }

    private func progress(_ used: Decimal?, _ limit: Decimal?) -> Double? {
        guard let used = used, let limit = limit, limit > 0 else { return nil }
        return min(max(NSDecimalNumber(decimal: used / limit).doubleValue, 0), 1)
    }
}

private struct DashboardWindowTitleUpdater: NSViewRepresentable {
    let title: String

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            view.window?.title = title
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            nsView.window?.title = title
        }
    }
}
