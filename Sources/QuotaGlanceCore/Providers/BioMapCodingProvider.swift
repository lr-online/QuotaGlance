import Foundation

public struct BioMapCodingProvider: UsageProvider {
    public static let keyInfoEndpoint = URL(
        string: "https://coding.biomap-int.com/key/info"
    )!
    public static let modelsEndpoint = URL(
        string: "https://coding.biomap-int.com/v1/models"
    )!
    public let id = ProviderID.bioMapCoding

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
            snapshot: try await requestKeyInfo(apiKey: apiKey)
        )
    }

    public func fetch(apiKey: String) async throws -> ProviderUsageSnapshot {
        try await requestKeyInfo(apiKey: apiKey)
    }

    public func fetch(
        apiKey: String,
        profile: ProviderProfile
    ) async throws -> ProviderUsageSnapshot {
        guard profile == Self.profile else {
            throw ProviderError.profileMismatch
        }
        return try await requestKeyInfo(apiKey: apiKey)
    }
}

private extension BioMapCodingProvider {
    func requestKeyInfo(apiKey: String) async throws -> ProviderUsageSnapshot {
        var request = URLRequest(url: Self.keyInfoEndpoint)
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await httpClient.data(for: request)
        if [403, 404, 405].contains(response.statusCode) {
            return try await requestModels(apiKey: apiKey)
        }
        try ProviderHTTPStatus.validate(response)

        do {
            let payload = try JSONDecoder().decode(KeyInfoResponse.self, from: data)
            guard payload.info.blocked != true else {
                throw ProviderError.providerInactive
            }

            let spend = payload.info.spend?.value
            let maximum = payload.info.maxBudget?.value
            if let maximum, maximum < 0 {
                throw ProviderError.invalidResponse
            }
            let currency = "USD"
            let spendMoney = spend.map { Money(amount: $0, currency: currency) }
            let maximumMoney = maximum.map { Money(amount: $0, currency: currency) }
            let remaining = spend.flatMap { spend in
                maximum.map { maximum in
                    Money(amount: maximum - spend, currency: currency)
                }
            }
            let duration = payload.info.budgetDuration?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let resetDescription = duration.flatMap {
                $0.isEmpty ? nil : "Budget period: \($0)"
            }

            return ProviderUsageSnapshot(
                spendingLimit: maximumMoney.map {
                    SpendingLimit(
                        label: "Key budget",
                        used: spendMoney,
                        limit: $0,
                        remaining: remaining,
                        resetDescription: resetDescription
                    )
                },
                spend: SpendSummary(total: spendMoney),
                providerStatus: "active",
                metricsUnavailableReason: spend == nil && maximum == nil
                    ? "Budget metrics unavailable for this key."
                    : nil,
                receivedAt: now()
            )
        } catch let error as ProviderError {
            throw error
        } catch {
            throw ProviderError.invalidResponse
        }
    }

    func requestModels(apiKey: String) async throws -> ProviderUsageSnapshot {
        var request = URLRequest(url: Self.modelsEndpoint)
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await httpClient.data(for: request)
        try ProviderHTTPStatus.validate(response)

        do {
            let payload = try JSONDecoder().decode(ModelList.self, from: data)
            let identifiers = payload.data.map {
                $0.id.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            guard payload.object == "list",
                  !identifiers.isEmpty,
                  identifiers.allSatisfy({ !$0.isEmpty }) else {
                throw ProviderError.invalidResponse
            }
            return ProviderUsageSnapshot(
                providerStatus: "connected",
                metricsUnavailableReason: "\(identifiers.count) models available. Budget metrics unavailable for this key.",
                receivedAt: now()
            )
        } catch let error as ProviderError {
            throw error
        } catch {
            throw ProviderError.invalidResponse
        }
    }

    struct KeyInfoResponse: Decodable {
        let info: KeyInfo
    }

    struct KeyInfo: Decodable {
        let spend: ProviderDecimal?
        let maxBudget: ProviderDecimal?
        let budgetDuration: String?
        let blocked: Bool?

        enum CodingKeys: String, CodingKey {
            case spend
            case maxBudget = "max_budget"
            case budgetDuration = "budget_duration"
            case blocked
        }
    }

    struct ModelList: Decodable {
        let object: String
        let data: [Model]
    }

    struct Model: Decodable {
        let id: String
    }
}
