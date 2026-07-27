import Foundation

public struct DeepSeekProvider: UsageProvider {
    public static let endpoint = URL(string: "https://api.deepseek.com/user/balance")!
    public let id = ProviderID.deepSeek

    private static let profile = ProviderProfile(
        region: .global,
        credentialKind: .standard
    )

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
        ProviderDetection(
            profile: Self.profile,
            snapshot: try await fetch(apiKey: apiKey)
        )
    }

    public func fetch(apiKey: String) async throws -> ProviderUsageSnapshot {
        try await requestBalance(apiKey: apiKey)
    }

    public func fetch(
        apiKey: String,
        profile: ProviderProfile
    ) async throws -> ProviderUsageSnapshot {
        guard profile == Self.profile else {
            throw ProviderError.profileMismatch
        }
        return try await requestBalance(apiKey: apiKey)
    }
}

private extension DeepSeekProvider {
    func requestBalance(apiKey: String) async throws -> ProviderUsageSnapshot {
        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await httpClient.data(for: request)
        try ProviderHTTPStatus.validate(response)

        do {
            let payload = try JSONDecoder().decode(Response.self, from: data)
            guard let balanceInfos = payload.balanceInfos, !balanceInfos.isEmpty else {
                throw ProviderError.invalidResponse
            }

            let balances = try balanceInfos.map { info in
                let currency = info.currency
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .uppercased()
                guard !currency.isEmpty, let totalBalance = info.totalBalance?.value else {
                    throw ProviderError.invalidResponse
                }

                var breakdown: [MonetaryValue] = []
                if let grantedBalance = info.grantedBalance?.value {
                    breakdown.append(
                        MonetaryValue(
                            label: "Granted",
                            value: Money(amount: grantedBalance, currency: currency)
                        )
                    )
                }
                if let toppedUpBalance = info.toppedUpBalance?.value {
                    breakdown.append(
                        MonetaryValue(
                            label: "Topped up",
                            value: Money(amount: toppedUpBalance, currency: currency)
                        )
                    )
                }

                return MonetaryBalance(
                    label: "Balance",
                    available: Money(amount: totalBalance, currency: currency),
                    breakdown: breakdown
                )
            }

            return ProviderUsageSnapshot(
                balances: balances,
                providerStatus: payload.isAvailable ? "active" : "unavailable",
                receivedAt: now()
            )
        } catch let error as ProviderError {
            throw error
        } catch {
            throw ProviderError.invalidResponse
        }
    }

    struct Response: Decodable {
        let isAvailable: Bool
        let balanceInfos: [BalanceInfo]?

        enum CodingKeys: String, CodingKey {
            case isAvailable = "is_available"
            case balanceInfos = "balance_infos"
        }
    }

    struct BalanceInfo: Decodable {
        let currency: String
        let totalBalance: ProviderDecimal?
        let grantedBalance: ProviderDecimal?
        let toppedUpBalance: ProviderDecimal?

        enum CodingKeys: String, CodingKey {
            case currency
            case totalBalance = "total_balance"
            case grantedBalance = "granted_balance"
            case toppedUpBalance = "topped_up_balance"
        }
    }
}
