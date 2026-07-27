import Foundation

public struct KimiProvider: UsageProvider {
    public static let chinaEndpoint = URL(
        string: "https://api.moonshot.cn/v1/users/me/balance"
    )!
    public static let internationalEndpoint = URL(
        string: "https://api.moonshot.ai/v1/users/me/balance"
    )!

    public let id = ProviderID.kimi

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
        do {
            return ProviderDetection(
                profile: Self.profile(for: preferredRegion),
                snapshot: try await requestBalance(
                    apiKey: apiKey,
                    region: preferredRegion
                )
            )
        } catch ProviderError.invalidCredential {
            let fallbackRegion: ProviderRegion = preferredRegion == .china
                ? .international
                : .china
            do {
                return ProviderDetection(
                    profile: Self.profile(for: fallbackRegion),
                    snapshot: try await requestBalance(
                        apiKey: apiKey,
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
        guard profile.credentialKind == .standard,
              let region = Self.supportedRegion(profile.region) else {
            throw ProviderError.profileMismatch
        }
        return try await requestBalance(apiKey: apiKey, region: region)
    }
}

private extension KimiProvider {
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
        ProviderProfile(region: region, credentialKind: .standard)
    }

    static func endpoint(for region: ProviderRegion) -> URL {
        region == .china ? chinaEndpoint : internationalEndpoint
    }

    static func currency(for region: ProviderRegion) -> String {
        region == .china ? "CNY" : "USD"
    }

    func requestBalance(
        apiKey: String,
        region: ProviderRegion
    ) async throws -> ProviderUsageSnapshot {
        var request = URLRequest(url: Self.endpoint(for: region))
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await httpClient.data(for: request)
        try ProviderHTTPStatus.validate(response)

        do {
            let payload = try JSONDecoder().decode(Response.self, from: data)
            guard payload.code == 0,
                  payload.status,
                  let available = payload.data?.availableBalance?.value else {
                throw ProviderError.invalidResponse
            }

            let currency = Self.currency(for: region)
            var breakdown: [MonetaryValue] = []
            if let cash = payload.data?.cashBalance?.value {
                breakdown.append(
                    MonetaryValue(
                        label: "Cash",
                        value: Money(amount: cash, currency: currency)
                    )
                )
            }
            if let voucher = payload.data?.voucherBalance?.value {
                breakdown.append(
                    MonetaryValue(
                        label: "Voucher",
                        value: Money(amount: voucher, currency: currency)
                    )
                )
            }

            return ProviderUsageSnapshot(
                balances: [
                    MonetaryBalance(
                        label: "Balance",
                        available: Money(amount: available, currency: currency),
                        breakdown: breakdown
                    )
                ],
                providerStatus: "active",
                receivedAt: now()
            )
        } catch let error as ProviderError {
            throw error
        } catch {
            throw ProviderError.invalidResponse
        }
    }

    struct Response: Decodable {
        let code: Int
        let status: Bool
        let data: BalanceData?
    }

    struct BalanceData: Decodable {
        let availableBalance: ProviderDecimal?
        let cashBalance: ProviderDecimal?
        let voucherBalance: ProviderDecimal?

        enum CodingKeys: String, CodingKey {
            case availableBalance = "available_balance"
            case cashBalance = "cash_balance"
            case voucherBalance = "voucher_balance"
        }
    }
}
