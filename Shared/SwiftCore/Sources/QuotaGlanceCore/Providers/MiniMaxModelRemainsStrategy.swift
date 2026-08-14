import Foundation

/// Named parse strategy `miniMaxModelRemains` (Contracts/README.md, "Named
/// parse strategies"): derives quota windows from MiniMax `model_remains`
/// entries. Direct windows win over interval/weekly windows, counted forms
/// win over percent forms, an absent status counts as active (`!= 0`), and
/// timestamps are epoch seconds or milliseconds (magnitude > 1e10 ⇒
/// milliseconds).
enum MiniMaxModelRemainsStrategy {
    static func quotaWindows(from value: SpecJSONValue?) -> [QuotaWindow] {
        guard case let .array(entries) = value else { return [] }
        return entries.flatMap(quotaWindows(for:))
    }

    static func quotaWindows(for entry: SpecJSONValue) -> [QuotaWindow] {
        if let direct = directQuotaWindow(for: entry) {
            return [direct]
        }

        var windows: [QuotaWindow] = []
        if decimal(entry, "current_interval_status") != 0,
           let interval = intervalQuotaWindow(for: entry) {
            windows.append(interval)
        }
        if decimal(entry, "current_weekly_status") != 0,
           let weekly = weeklyQuotaWindow(for: entry) {
            windows.append(weekly)
        }
        return windows
    }

    private static func directQuotaWindow(for entry: SpecJSONValue) -> QuotaWindow? {
        let limit = decimal(entry, "total")
        let suppliedUsed = decimal(entry, "used")
        let suppliedRemaining = decimal(entry, "remains")
        guard limit != nil || suppliedUsed != nil || suppliedRemaining != nil else {
            return nil
        }

        let used = suppliedUsed ?? subtract(limit, suppliedRemaining)
        let remaining = suppliedRemaining ?? subtract(limit, suppliedUsed)
        return QuotaWindow(
            label: normalizedLabel(string(entry, "label"))
                ?? "\(normalizedModelName(string(entry, "model_name"))) quota",
            used: used,
            limit: limit,
            remaining: remaining,
            unit: normalizedLabel(string(entry, "unit")) ?? "requests",
            resetsAt: providerDate(decimal(entry, "reset_time") ?? decimal(entry, "end_time"))
        )
    }

    private static func intervalQuotaWindow(for entry: SpecJSONValue) -> QuotaWindow? {
        let label = isFiveHourWindow(
            start: decimal(entry, "start_time"),
            end: decimal(entry, "end_time")
        )
            ? "\(normalizedModelName(string(entry, "model_name"))) 5-hour quota"
            : "\(normalizedModelName(string(entry, "model_name"))) quota"
        return countedOrPercentWindow(
            label: label,
            total: decimal(entry, "current_interval_total_count"),
            used: decimal(entry, "current_interval_usage_count"),
            remainingPercent: decimal(entry, "current_interval_remaining_percent"),
            resetsAt: decimal(entry, "end_time")
        )
    }

    private static func weeklyQuotaWindow(for entry: SpecJSONValue) -> QuotaWindow? {
        countedOrPercentWindow(
            label: "\(normalizedModelName(string(entry, "model_name"))) weekly quota",
            total: decimal(entry, "current_weekly_total_count"),
            used: decimal(entry, "current_weekly_usage_count"),
            remainingPercent: decimal(entry, "current_weekly_remaining_percent"),
            resetsAt: decimal(entry, "weekly_end_time")
        )
    }

    private static func countedOrPercentWindow(
        label: String,
        total: Decimal?,
        used: Decimal?,
        remainingPercent: Decimal?,
        resetsAt: Decimal?
    ) -> QuotaWindow? {
        if total.map({ $0 > 0 }) == true || used.map({ $0 > 0 }) == true {
            return QuotaWindow(
                label: label,
                used: used,
                limit: total,
                remaining: subtract(total, used),
                unit: "requests",
                resetsAt: providerDate(resetsAt)
            )
        }
        if let percentage = remainingPercent {
            let remaining = max(0, min(100, percentage))
            return QuotaWindow(
                label: label,
                used: 100 - remaining,
                limit: 100,
                remaining: remaining,
                unit: "%",
                resetsAt: providerDate(resetsAt)
            )
        }
        return nil
    }

    private static func subtract(_ lhs: Decimal?, _ rhs: Decimal?) -> Decimal? {
        guard let lhs, let rhs else { return nil }
        return lhs - rhs
    }

    private static func normalizedLabel(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func normalizedModelName(_ value: String?) -> String {
        normalizedLabel(value) ?? "Token Plan"
    }

    private static func providerDate(_ value: Decimal?) -> Date? {
        guard let value else { return nil }
        var seconds = NSDecimalNumber(decimal: value).doubleValue
        if abs(seconds) > 10_000_000_000 {
            seconds /= 1_000
        }
        return Date(timeIntervalSince1970: seconds)
    }

    private static func isFiveHourWindow(start: Decimal?, end: Decimal?) -> Bool {
        guard let startDate = providerDate(start), let endDate = providerDate(end) else {
            return false
        }
        return abs(endDate.timeIntervalSince(startDate) - 18_000) < 1
    }

    private static func decimal(_ entry: SpecJSONValue, _ key: String) -> Decimal? {
        guard case let .object(fields) = entry else { return nil }
        return SpecEngine.decimal(fields[key])?.value
    }

    private static func string(_ entry: SpecJSONValue, _ key: String) -> String? {
        guard case let .object(fields) = entry,
              case let .string(value)? = fields[key] else {
            return nil
        }
        return value
    }
}
