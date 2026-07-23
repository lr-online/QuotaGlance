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
                    dashboard(presentation)
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
                }
                .buttonStyle(.borderless)
                .frame(width: 28, height: 28)
                .disabled(model.accounts.isEmpty)
                .help("Refresh")
            }
        }
    }

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
    private func quotaSection(_ quota: MenuBarQuotaPresentation) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if let fraction = quota.fraction {
                ProgressView(value: fraction)
                    .progressViewStyle(.linear)
                    .accessibilityLabel("Quota used")
                    .accessibilityValue(
                        fraction.formatted(
                            .percent.precision(.fractionLength(0))
                        )
                    )
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

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "gauge.open.with.lines.needle.33percent")
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
        case .stale:
            Detail(text: "Saved Data", icon: "clock.badge.exclamationmark", color: .orange)
        case .unavailable:
            Detail(text: "Unavailable", icon: "xmark.circle.fill", color: .red)
        case .empty:
            Detail(text: "No Data", icon: "minus.circle", color: .secondary)
        }
    }
}
