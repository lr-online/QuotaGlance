import AppKit
import QuotaGlanceCore
import SwiftUI
import WidgetKit

struct NCWidgetMediumView: View {
    let entry: NCWidgetEntry

    private let contentInset: CGFloat = 14

    var body: some View {
        Group {
            switch entry.presentation.state {
            case .noSnapshot:
                unavailableView(title: "No Data", icon: "gauge.open.with.lines.needle.33percent")
            case .deletedAccount:
                unavailableView(title: "Account Unavailable", icon: "person.crop.circle.badge.xmark")
            case .available:
                mediumView
            }
        }
        .padding(contentInset)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(Color(nsColor: .windowBackgroundColor))
        .widgetURL(entry.presentation.deepLink)
    }

    private var mediumView: some View {
        GeometryReader { proxy in
            let chartWidth = min(proxy.size.width * 0.42, 150)
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    widgetHeader
                    primaryMetricBlock
                    if entry.presentation.todayActualCost != nil
                        || entry.presentation.todayRequests != nil {
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
                    Spacer(minLength: 0)
                    freshness
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)

                if !entry.presentation.dailyUsage.isEmpty {
                    NCWidgetUsageChart(dailyUsage: Array(entry.presentation.dailyUsage.suffix(7)))
                        .frame(width: chartWidth, height: proxy.size.height)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
        }
    }

    private var widgetHeader: some View {
        HStack(spacing: 6) {
            Text(entry.presentation.title)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Spacer(minLength: 4)
            Circle()
                .fill(presentationColor)
                .frame(width: 7, height: 7)
        }
    }

    @ViewBuilder
    private var primaryMetricBlock: some View {
        if entry.presentation.balances.count > 1 {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(entry.presentation.balances.prefix(2), id: \.currency) { balance in
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(MoneyFormatter.widgetString(balance))
                            .font(.system(size: 18, weight: .semibold, design: .rounded))
                            .lineLimit(1)
                            .minimumScaleFactor(0.55)
                        Spacer(minLength: 4)
                        Text("\(balance.currency)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
        } else if let metric = entry.presentation.primaryMetric {
            VStack(alignment: .leading, spacing: 1) {
                Text(PrimaryMetricFormatter.string(metric.value))
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.55)
                Text(primaryMetricLabel(metric))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        } else if let reason = entry.presentation.metricsUnavailableReason {
            VStack(alignment: .leading, spacing: 1) {
                Text("Connected")
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(reason)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        } else {
            VStack(alignment: .leading, spacing: 1) {
                Text("--")
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                Text("No metric")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func primaryMetricLabel(_ metric: PrimaryMetric) -> String {
        guard entry.presentation.balances.isEmpty,
              let fallback = entry.presentation.accountRows.first(where: {
                  $0.primaryMetric == metric
              }) else {
            return metric.label
        }
        return "\(fallback.displayName) · \(metric.label)"
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
        .font(.caption2)
    }

    @ViewBuilder
    private var freshness: some View {
        if let date = entry.presentation.lastSuccessAt {
            Text(date, style: .relative)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
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
}

private struct NCWidgetUsageChart: View {
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
        GeometryReader { proxy in
            let barCount = max(dailyUsage.count, 1)
            let spacing = min(4, proxy.size.width / CGFloat(barCount * 4))
            HStack(alignment: .bottom, spacing: spacing) {
                ForEach(Array(dailyUsage.enumerated()), id: \.element.date) { index, day in
                    let value = NSDecimalNumber(decimal: day.actualCost.amount).doubleValue
                    let height = max(2, proxy.size.height * value / maximum)
                    RoundedRectangle(cornerRadius: 2)
                        .fill(index == dailyUsage.count - 1
                            ? Color.accentColor
                            : Color.secondary.opacity(0.25))
                        .frame(maxWidth: .infinity)
                        .frame(height: height)
                        .frame(maxHeight: .infinity, alignment: .bottom)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .bottom)
        }
        .accessibilityLabel("Seven day usage")
    }
}
