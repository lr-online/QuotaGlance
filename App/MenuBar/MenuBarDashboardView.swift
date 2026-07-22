import AppKit
import QuotaGlanceCore
import SwiftUI

struct MenuBarDashboardView: View {
    let model: AppModel

    private var selection: DashboardSelection {
        model.selectedAccountID.map(DashboardSelection.account) ?? .allAccounts
    }

    private var presentation: DashboardPresentation? {
        guard let envelope = model.latestEnvelope else { return nil }
        return DashboardPresenter.make(selection: selection, envelope: envelope)
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
            .padding(14)

            Divider()

            footer
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
        }
        .frame(width: 360)
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

    private func dashboard(_ presentation: DashboardPresentation) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text(presentation.remaining.map { MoneyFormatter.string($0) } ?? "--")
                    .font(.system(size: 32, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                    .accessibilityLabel("Remaining balance")

                statusLabel(presentation.status)
            }

            HStack(spacing: 0) {
                metric(
                    title: "Today",
                    value: presentation.todayActualCost.map {
                        MoneyFormatter.string($0)
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

            if !presentation.dailyUsage.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Last 7 Days")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    UsageChartView(dailyUsage: presentation.dailyUsage)
                }
            }

            if case .allAccounts = selection {
                attentionSection(presentation.accountRows)
            } else if let usage = presentation.usage {
                accountDetails(usage)
            }

            if let lastSuccessAt = presentation.lastSuccessAt {
                HStack(spacing: 5) {
                    Image(systemName: "clock")
                    Text(lastSuccessAt, style: .relative)
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
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
                .font(.system(.body, design: .rounded, weight: .medium))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func attentionSection(_ accounts: [AccountSnapshot]) -> some View {
        let attention = accounts.filter {
            switch $0.health {
            case .healthy:
                false
            case .belowThreshold, .stale, .unavailable:
                true
            }
        }
        if !attention.isEmpty {
            VStack(alignment: .leading, spacing: 7) {
                Text("Attention")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ForEach(attention) { account in
                    HStack(spacing: 7) {
                        Circle()
                            .fill(color(for: DashboardPresenterStatus.health(account.health)))
                            .frame(width: 7, height: 7)
                        Text(account.displayName)
                            .lineLimit(1)
                        Spacer()
                        if let remaining = account.remaining {
                            Text(MoneyFormatter.string(remaining))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    .font(.caption)
                }
            }
        }
    }

    @ViewBuilder
    private func accountDetails(_ usage: ProviderUsageSnapshot) -> some View {
        if usage.quotaLimit != nil || usage.quotaUsed != nil {
            HStack(spacing: 14) {
                if let used = usage.quotaUsed {
                    metric(title: "Used", value: MoneyFormatter.string(used))
                }
                if let limit = usage.quotaLimit {
                    metric(title: "Limit", value: MoneyFormatter.string(limit))
                }
            }
        }

        if !usage.modelUsage.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("Models")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ForEach(usage.modelUsage.prefix(4)) { model in
                    HStack {
                        Text(model.model)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        Text(model.actualCost.map { MoneyFormatter.string($0) } ?? "--")
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
            SettingsLink {
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
        HStack {
            SettingsLink {
                Label("Settings", systemImage: "gearshape")
            }
            Spacer()
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
