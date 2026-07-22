import QuotaGlanceCore
import SwiftUI

struct UsageChartView: View {
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
        HStack(alignment: .bottom, spacing: 6) {
            ForEach(Array(dailyUsage.enumerated()), id: \.element.date) { index, day in
                VStack(spacing: 4) {
                    GeometryReader { proxy in
                        let value = NSDecimalNumber(
                            decimal: day.actualCost.amount
                        ).doubleValue
                        let height = max(2, proxy.size.height * value / maximum)

                        RoundedRectangle(cornerRadius: 2)
                            .fill(index == dailyUsage.count - 1 ? Color.accentColor : Color.secondary.opacity(0.28))
                            .frame(height: height)
                            .frame(maxHeight: .infinity, alignment: .bottom)
                    }
                    .frame(height: 54)

                    Text(dayLabel(day.date))
                        .font(.caption2)
                        .foregroundStyle(index == dailyUsage.count - 1 ? .primary : .secondary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity)
                .help(MoneyFormatter.string(day.actualCost))
            }
        }
        .frame(height: 72)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Seven day usage")
    }

    private func dayLabel(_ date: String) -> String {
        String(date.suffix(2))
    }
}
