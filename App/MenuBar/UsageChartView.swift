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
