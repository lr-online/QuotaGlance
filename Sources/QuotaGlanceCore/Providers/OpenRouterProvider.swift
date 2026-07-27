import Foundation

public struct OpenRouterProvider: UsageProvider {
    public static let keyEndpoint = URL(string: "https://openrouter.ai/api/v1/key")!
    public static let creditsEndpoint = URL(
        string: "https://openrouter.ai/api/v1/credits"
    )!

    public let id = ProviderID.openRouter

    private let httpClient: any HTTPClient
    private let now: @Sendable () -> Date

    public init(
        httpClient: any HTTPClient = URLSessionHTTPClient(),
        now: @escaping @Sendable () -> Date = { .now }
    ) {
        self.httpClient = httpClient
        self.now = now
    }

    public func detect(apiKey: String) async throws -> ProviderDetection {
        let key = try await requestKey(apiKey: apiKey)
        let kind: ProviderCredentialKind = key.isManagementKey
            ? .management
            : .standard
        return ProviderDetection(
            profile: ProviderProfile(region: .global, credentialKind: kind),
            snapshot: try await snapshot(apiKey: apiKey, key: key)
        )
    }

    public func fetch(apiKey: String) async throws -> ProviderUsageSnapshot {
        try await detect(apiKey: apiKey).snapshot
    }

    public func fetch(
        apiKey: String,
        profile: ProviderProfile
    ) async throws -> ProviderUsageSnapshot {
        guard profile.region == .global,
              profile.credentialKind == .standard
                || profile.credentialKind == .management else {
            throw ProviderError.profileMismatch
        }

        let key = try await requestKey(apiKey: apiKey)
        let observedKind: ProviderCredentialKind = key.isManagementKey
            ? .management
            : .standard
        guard observedKind == profile.credentialKind else {
            throw ProviderError.profileMismatch
        }
        return try await snapshot(apiKey: apiKey, key: key)
    }
}

private extension OpenRouterProvider {
    func snapshot(
        apiKey: String,
        key: KeyData
    ) async throws -> ProviderUsageSnapshot {
        let currency = "USD"
        let spendingLimit = key.limit.map { limit in
            SpendingLimit(
                label: "Key limit",
                used: key.usage.map { Money(amount: $0, currency: currency) },
                limit: Money(amount: limit, currency: currency),
                remaining: key.limitRemaining.map {
                    Money(amount: $0, currency: currency)
                }
            )
        }
        let spend = SpendSummary(
            today: key.usageDaily.map { Money(amount: $0, currency: currency) },
            week: key.usageWeekly.map { Money(amount: $0, currency: currency) },
            month: key.usageMonthly.map { Money(amount: $0, currency: currency) },
            total: key.usage.map { Money(amount: $0, currency: currency) }
        )

        let balances: [MonetaryBalance]
        if key.isManagementKey {
            let credits = try await requestCredits(apiKey: apiKey)
            balances = [
                MonetaryBalance(
                    label: "Credits",
                    available: Money(
                        amount: credits.totalCredits - credits.totalUsage,
                        currency: currency
                    )
                )
            ]
        } else {
            balances = []
        }

        return ProviderUsageSnapshot(
            balances: balances,
            spendingLimit: spendingLimit,
            spend: spend,
            providerStatus: "active",
            receivedAt: now()
        )
    }

    func requestKey(apiKey: String) async throws -> KeyData {
        let data = try await request(apiKey: apiKey, endpoint: Self.keyEndpoint)
        do {
            let envelope = try JSONDecoder().decode(KeyEnvelope.self, from: data)
            guard let isManagementKey = envelope.data?.isManagementKey else {
                throw ProviderError.invalidResponse
            }
            return KeyData(
                isManagementKey: isManagementKey,
                usage: envelope.data?.usage?.value,
                limit: envelope.data?.limit?.value,
                limitRemaining: envelope.data?.limitRemaining?.value,
                usageDaily: envelope.data?.usageDaily?.value,
                usageWeekly: envelope.data?.usageWeekly?.value,
                usageMonthly: envelope.data?.usageMonthly?.value
            )
        } catch let error as ProviderError {
            throw error
        } catch {
            throw ProviderError.invalidResponse
        }
    }

    func requestCredits(apiKey: String) async throws -> CreditsData {
        let data = try await request(apiKey: apiKey, endpoint: Self.creditsEndpoint)
        do {
            let envelope = try JSONDecoder().decode(CreditsEnvelope.self, from: data)
            guard let totalCredits = envelope.data?.totalCredits?.value,
                  let totalUsage = envelope.data?.totalUsage?.value else {
                throw ProviderError.invalidResponse
            }
            return CreditsData(totalCredits: totalCredits, totalUsage: totalUsage)
        } catch let error as ProviderError {
            throw error
        } catch {
            throw ProviderError.invalidResponse
        }
    }

    func request(apiKey: String, endpoint: URL) async throws -> Data {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await httpClient.data(for: request)
        try ProviderHTTPStatus.validate(response)
        return data
    }

    struct KeyData: Sendable {
        let isManagementKey: Bool
        let usage: Decimal?
        let limit: Decimal?
        let limitRemaining: Decimal?
        let usageDaily: Decimal?
        let usageWeekly: Decimal?
        let usageMonthly: Decimal?
    }

    struct CreditsData: Sendable {
        let totalCredits: Decimal
        let totalUsage: Decimal
    }

    struct KeyEnvelope: Decodable {
        let data: KeyResponse?
    }

    struct KeyResponse: Decodable {
        let isManagementKey: Bool?
        let usage: ProviderDecimal?
        let limit: ProviderDecimal?
        let limitRemaining: ProviderDecimal?
        let usageDaily: ProviderDecimal?
        let usageWeekly: ProviderDecimal?
        let usageMonthly: ProviderDecimal?

        enum CodingKeys: String, CodingKey {
            case isManagementKey = "is_management_key"
            case usage
            case limit
            case limitRemaining = "limit_remaining"
            case usageDaily = "usage_daily"
            case usageWeekly = "usage_weekly"
            case usageMonthly = "usage_monthly"
        }
    }

    struct CreditsEnvelope: Decodable {
        let data: CreditsResponse?
    }

    struct CreditsResponse: Decodable {
        let totalCredits: ProviderDecimal?
        let totalUsage: ProviderDecimal?

        enum CodingKeys: String, CodingKey {
            case totalCredits = "total_credits"
            case totalUsage = "total_usage"
        }
    }
}
