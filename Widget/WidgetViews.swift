import AppKit
import QuotaGlanceCore
import SwiftUI
import WidgetKit

struct QuotaGlanceWidgetView: View {
    @Environment(\.widgetFamily) private var family

    let entry: QuotaGlanceWidgetEntry

    var body: some View {
        Group {
            switch entry.presentation.state {
            case .noSnapshot:
                unavailableView(title: "No Data", icon: "gauge.open.with.lines.needle.33percent")
            case .deletedAccount:
                unavailableView(title: "Account Unavailable", icon: "person.crop.circle.badge.xmark")
            case .available:
                switch family {
                case .systemSmall:
                    smallView
                case .systemMedium:
                    mediumView
                default:
                    largeView
                }
            }
        }
        .containerBackground(for: .widget) {
            Color(nsColor: .windowBackgroundColor)
        }
        .widgetURL(entry.presentation.deepLink)
    }

    private var smallView: some View {
        VStack(alignment: .leading, spacing: 8) {
            widgetHeader
            Spacer(minLength: 2)
            balanceText(size: 24)
            metricLine(
                label: "Today",
                value: entry.presentation.todayActualCost.map {
                    MoneyFormatter.widgetString($0)
                } ?? "--"
            )
            freshness
        }
    }

    private var mediumView: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                widgetHeader
                Spacer(minLength: 2)
                balanceText(size: 27)
                metricLine(
                    label: "Today",
                    value: entry.presentation.todayActualCost.map {
                        MoneyFormatter.widgetString($0)
                    } ?? "--"
                )
                metricLine(
                    label: "Requests",
                    value: entry.presentation.todayRequests?.formatted() ?? "--"
                )
                freshness
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            WidgetUsageChart(dailyUsage: entry.presentation.dailyUsage)
                .frame(maxWidth: .infinity)
        }
    }

    private var largeView: some View {
        VStack(alignment: .leading, spacing: 12) {
            widgetHeader
            balanceText(size: 30)

            HStack(spacing: 20) {
                metricLine(
                    label: "Today",
                    value: entry.presentation.todayActualCost.map {
                        MoneyFormatter.widgetString($0)
                    } ?? "--"
                )
                metricLine(
                    label: "Requests",
                    value: entry.presentation.todayRequests?.formatted() ?? "--"
                )
            }

            WidgetUsageChart(dailyUsage: entry.presentation.dailyUsage)
                .frame(height: 74)

            if !entry.presentation.accountRows.isEmpty {
                VStack(spacing: 6) {
                    ForEach(entry.presentation.accountRows.prefix(5)) { account in
                        HStack(spacing: 7) {
                            Circle()
                                .fill(statusColor(account.health))
                                .frame(width: 7, height: 7)
                            Text(account.displayName)
                                .lineLimit(1)
                            Spacer()
                            Text(
                                account.remaining.map {
                                    MoneyFormatter.widgetString($0)
                                } ?? "--"
                            )
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        .font(.caption)
                    }
                }
            }

            freshness
        }
    }

    private var widgetHeader: some View {
        HStack(spacing: 6) {
            Text(entry.presentation.title)
                .font(.headline)
                .lineLimit(1)
            Spacer(minLength: 4)
            Circle()
                .fill(presentationColor)
                .frame(width: 7, height: 7)
        }
    }

    private func balanceText(size: CGFloat) -> some View {
        Text(
            entry.presentation.remaining.map {
                MoneyFormatter.widgetString($0)
            } ?? "--"
        )
            .font(.system(size: size, weight: .semibold, design: .rounded))
            .lineLimit(1)
            .minimumScaleFactor(0.6)
    }

    private func metricLine(label: String, value: String) -> some View {
        HStack(spacing: 5) {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer(minLength: 4)
            Text(value)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .font(.caption)
    }

    @ViewBuilder
    private var freshness: some View {
        if let date = entry.presentation.lastSuccessAt {
            Text(date, style: .relative)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private func unavailableView(title: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(.secondary)
            Text("QuotaGlance")
                .font(.headline)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var presentationColor: Color {
        switch entry.presentation.state {
        case let .available(status):
            switch status {
            case .healthy: .green
            case .belowThreshold, .partial, .stale: .orange
            case .unavailable: .red
            case .empty: .secondary
            }
        case .noSnapshot, .deletedAccount:
            .secondary
        }
    }

    private func statusColor(_ health: AccountHealth) -> Color {
        switch health {
        case .healthy: .green
        case .belowThreshold, .stale: .orange
        case .unavailable: .red
        }
    }
}

private struct WidgetUsageChart: View {
    let dailyUsage: [DailyUsage]

    private var maximum: Double {
        max(
            dailyUsage.map {
                NSDecimalNumber(decimal: $0.actualCost.amount).doubleValue
            }.max() ?? 0,
            0.000_001
        )
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 5) {
            ForEach(Array(dailyUsage.enumerated()), id: \.element.date) { index, day in
                GeometryReader { proxy in
                    let value = NSDecimalNumber(decimal: day.actualCost.amount).doubleValue
                    let height = max(2, proxy.size.height * value / maximum)
                    RoundedRectangle(cornerRadius: 2)
                        .fill(index == dailyUsage.count - 1 ? Color.accentColor : Color.secondary.opacity(0.25))
                        .frame(height: height)
                        .frame(maxHeight: .infinity, alignment: .bottom)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .frame(minHeight: 50)
        .accessibilityLabel("Seven day usage")
    }
}
