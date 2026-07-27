import Foundation

public struct MiniMaxProvider: UsageProvider {
    public static let chinaEndpoint = URL(
        string: "https://www.minimaxi.com/v1/token_plan/remains"
    )!
    public static let internationalEndpoint = URL(
        string: "https://www.minimax.io/v1/token_plan/remains"
    )!

    public let id = ProviderID.miniMax

    private let httpClient: any HTTPClient
    private let preferredRegion: ProviderRegion
    private let now: @Sendable () -> Date

    public init(
        httpClient: any HTTPClient = URLSessionHTTPClient(),
        preferredRegion: ProviderRegion? = nil,
        now: @escaping @Sendable () -> Date = { .now }
    ) {
        self.httpClient = httpClient
        self.preferredRegion = preferredRegion.flatMap(Self.supportedRegion)
            ?? Self.localePreferredRegion()
        self.now = now
    }

    public func detect(apiKey: String) async throws -> ProviderDetection {
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        try Self.validateCredential(key)

        do {
            return ProviderDetection(
                profile: Self.profile(for: preferredRegion),
                snapshot: try await requestQuota(apiKey: key, region: preferredRegion)
            )
        } catch ProviderError.invalidCredential {
            let fallbackRegion: ProviderRegion = preferredRegion == .china
                ? .international
                : .china
            do {
                return ProviderDetection(
                    profile: Self.profile(for: fallbackRegion),
                    snapshot: try await requestQuota(
                        apiKey: key,
                        region: fallbackRegion
                    )
                )
            } catch ProviderError.invalidCredential {
                throw ProviderError.regionDetectionFailed
            }
        }
    }

    public func fetch(apiKey: String) async throws -> ProviderUsageSnapshot {
        try await detect(apiKey: apiKey).snapshot
    }

    public func fetch(
        apiKey: String,
        profile: ProviderProfile
    ) async throws -> ProviderUsageSnapshot {
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        try Self.validateCredential(key)
        guard profile.credentialKind == .tokenPlan,
              let region = Self.supportedRegion(profile.region) else {
            throw ProviderError.profileMismatch
        }
        return try await requestQuota(apiKey: key, region: region)
    }
}

private extension MiniMaxProvider {
    static func validateCredential(_ apiKey: String) throws {
        if apiKey.lowercased().hasPrefix("sk-api-") {
            throw ProviderError.unsupportedCredential
        }
    }

    static func supportedRegion(_ region: ProviderRegion) -> ProviderRegion? {
        switch region {
        case .china, .international:
            region
        case .global:
            nil
        }
    }

    static func localePreferredRegion() -> ProviderRegion {
        let regionCode: String?
        if #available(macOS 13, *) {
            regionCode = Locale.current.region?.identifier
        } else {
            regionCode = Locale.current.regionCode
        }
        return regionCode?.uppercased() == "CN" ? .china : .international
    }

    static func profile(for region: ProviderRegion) -> ProviderProfile {
        ProviderProfile(region: region, credentialKind: .tokenPlan)
    }

    static func endpoint(for region: ProviderRegion) -> URL {
        region == .china ? chinaEndpoint : internationalEndpoint
    }

    func requestQuota(
        apiKey: String,
        region: ProviderRegion
    ) async throws -> ProviderUsageSnapshot {
        var request = URLRequest(url: Self.endpoint(for: region))
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let (data, response) = try await httpClient.data(for: request)
        try ProviderHTTPStatus.validate(response)

        do {
            let payload = try JSONDecoder().decode(Response.self, from: data)
            guard let statusCode = payload.baseResponse?.statusCode?.value else {
                throw ProviderError.invalidResponse
            }
            if statusCode == 1004 {
                throw ProviderError.invalidCredential
            }
            guard statusCode == 0 else {
                throw ProviderError.invalidResponse
            }

            let windows = (payload.modelRemains ?? []).flatMap(Self.quotaWindows)
            guard !windows.isEmpty else {
                throw ProviderError.invalidResponse
            }
            return ProviderUsageSnapshot(
                quotaWindows: windows,
                providerStatus: "active",
                receivedAt: now()
            )
        } catch let error as ProviderError {
            throw error
        } catch {
            throw ProviderError.invalidResponse
        }
    }

    static func quotaWindows(for entry: ModelRemain) -> [QuotaWindow] {
        if let direct = directQuotaWindow(for: entry) {
            return [direct]
        }

        var windows: [QuotaWindow] = []
        if entry.currentIntervalStatus?.value != 0,
           let interval = intervalQuotaWindow(for: entry) {
            windows.append(interval)
        }
        if entry.currentWeeklyStatus?.value != 0,
           let weekly = weeklyQuotaWindow(for: entry) {
            windows.append(weekly)
        }
        return windows
    }

    static func directQuotaWindow(for entry: ModelRemain) -> QuotaWindow? {
        let limit = entry.total?.value
        let suppliedUsed = entry.used?.value
        let suppliedRemaining = entry.remains?.value
        guard limit != nil || suppliedUsed != nil || suppliedRemaining != nil else {
            return nil
        }

        let used = suppliedUsed ?? subtract(limit, suppliedRemaining)
        let remaining = suppliedRemaining ?? subtract(limit, suppliedUsed)
        return QuotaWindow(
            label: normalizedLabel(entry.label)
                ?? "\(normalizedModelName(entry.modelName)) quota",
            used: used,
            limit: limit,
            remaining: remaining,
            unit: normalizedLabel(entry.unit) ?? "requests",
            resetsAt: providerDate(entry.resetTime ?? entry.endTime)
        )
    }

    static func intervalQuotaWindow(for entry: ModelRemain) -> QuotaWindow? {
        let label = isFiveHourWindow(start: entry.startTime, end: entry.endTime)
            ? "\(normalizedModelName(entry.modelName)) 5-hour quota"
            : "\(normalizedModelName(entry.modelName)) quota"
        return countedOrPercentWindow(
            label: label,
            total: entry.currentIntervalTotalCount,
            used: entry.currentIntervalUsageCount,
            remainingPercent: entry.currentIntervalRemainingPercent,
            resetsAt: entry.endTime
        )
    }

    static func weeklyQuotaWindow(for entry: ModelRemain) -> QuotaWindow? {
        countedOrPercentWindow(
            label: "\(normalizedModelName(entry.modelName)) weekly quota",
            total: entry.currentWeeklyTotalCount,
            used: entry.currentWeeklyUsageCount,
            remainingPercent: entry.currentWeeklyRemainingPercent,
            resetsAt: entry.weeklyEndTime
        )
    }

    static func countedOrPercentWindow(
        label: String,
        total: ProviderDecimal?,
        used: ProviderDecimal?,
        remainingPercent: ProviderDecimal?,
        resetsAt: ProviderDecimal?
    ) -> QuotaWindow? {
        let totalValue = total?.value
        let usedValue = used?.value
        if totalValue.map({ $0 > 0 }) == true || usedValue.map({ $0 > 0 }) == true {
            return QuotaWindow(
                label: label,
                used: usedValue,
                limit: totalValue,
                remaining: subtract(totalValue, usedValue),
                unit: "requests",
                resetsAt: providerDate(resetsAt)
            )
        }
        if let percentage = remainingPercent?.value {
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

    static func subtract(_ lhs: Decimal?, _ rhs: Decimal?) -> Decimal? {
        guard let lhs, let rhs else { return nil }
        return lhs - rhs
    }

    static func normalizedLabel(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    static func normalizedModelName(_ value: String?) -> String {
        normalizedLabel(value) ?? "Token Plan"
    }

    static func providerDate(_ value: ProviderDecimal?) -> Date? {
        guard let decimal = value?.value else { return nil }
        var seconds = NSDecimalNumber(decimal: decimal).doubleValue
        if abs(seconds) > 10_000_000_000 {
            seconds /= 1_000
        }
        return Date(timeIntervalSince1970: seconds)
    }

    static func isFiveHourWindow(
        start: ProviderDecimal?,
        end: ProviderDecimal?
    ) -> Bool {
        guard let startDate = providerDate(start), let endDate = providerDate(end) else {
            return false
        }
        return abs(endDate.timeIntervalSince(startDate) - 18_000) < 1
    }

    struct Response: Decodable {
        let modelRemains: [ModelRemain]?
        let baseResponse: BaseResponse?

        enum CodingKeys: String, CodingKey {
            case modelRemains = "model_remains"
            case baseResponse = "base_resp"
        }
    }

    struct BaseResponse: Decodable {
        let statusCode: ProviderDecimal?

        enum CodingKeys: String, CodingKey {
            case statusCode = "status_code"
        }
    }

    struct ModelRemain: Decodable {
        let modelName: String?
        let label: String?
        let unit: String?
        let remains: ProviderDecimal?
        let total: ProviderDecimal?
        let used: ProviderDecimal?
        let resetTime: ProviderDecimal?
        let startTime: ProviderDecimal?
        let endTime: ProviderDecimal?
        let currentIntervalTotalCount: ProviderDecimal?
        let currentIntervalUsageCount: ProviderDecimal?
        let currentIntervalStatus: ProviderDecimal?
        let currentIntervalRemainingPercent: ProviderDecimal?
        let currentWeeklyTotalCount: ProviderDecimal?
        let currentWeeklyUsageCount: ProviderDecimal?
        let currentWeeklyStatus: ProviderDecimal?
        let currentWeeklyRemainingPercent: ProviderDecimal?
        let weeklyEndTime: ProviderDecimal?

        enum CodingKeys: String, CodingKey {
            case modelName = "model_name"
            case label
            case unit
            case remains
            case total
            case used
            case resetTime = "reset_time"
            case startTime = "start_time"
            case endTime = "end_time"
            case currentIntervalTotalCount = "current_interval_total_count"
            case currentIntervalUsageCount = "current_interval_usage_count"
            case currentIntervalStatus = "current_interval_status"
            case currentIntervalRemainingPercent = "current_interval_remaining_percent"
            case currentWeeklyTotalCount = "current_weekly_total_count"
            case currentWeeklyUsageCount = "current_weekly_usage_count"
            case currentWeeklyStatus = "current_weekly_status"
            case currentWeeklyRemainingPercent = "current_weekly_remaining_percent"
            case weeklyEndTime = "weekly_end_time"
        }
    }
}
