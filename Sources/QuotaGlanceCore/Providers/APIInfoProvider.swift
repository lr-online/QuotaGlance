import Foundation

public struct APIInfoProvider: UsageProvider {
    public static let endpoint = URL(string: "https://www.api-info.net/v1/usage")!

    private let httpClient: any HTTPClient
    private let now: @Sendable () -> Date

    public init(
        httpClient: any HTTPClient = URLSessionHTTPClient(),
        now: @escaping @Sendable () -> Date = { .now }
    ) {
        self.httpClient = httpClient
        self.now = now
    }

    public func fetch(apiKey: String) async throws -> ProviderUsageSnapshot {
        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await httpClient.data(for: request)
        switch response.statusCode {
        case 200..<300:
            break
        case 401, 403:
            throw ProviderError.invalidCredential
        case 429:
            throw ProviderError.rateLimited
        default:
            throw ProviderError.httpStatus(response.statusCode)
        }

        do {
            let payload = try JSONDecoder().decode(Response.self, from: data)
            guard payload.isValid else {
                throw ProviderError.providerInactive
            }
            guard let remaining = payload.remaining else {
                throw ProviderError.invalidResponse
            }
            guard let currency = payload.unit, !currency.isEmpty else {
                throw ProviderError.invalidResponse
            }

            return ProviderUsageSnapshot(
                remaining: Money(amount: remaining, currency: currency),
                quotaLimit: payload.quota?.limit.map {
                    Money(amount: $0, currency: currency)
                },
                quotaUsed: payload.quota?.used.map {
                    Money(amount: $0, currency: currency)
                },
                today: payload.usage?.today.map {
                    $0.snapshot(currency: currency)
                },
                total: payload.usage?.total.map {
                    $0.snapshot(currency: currency)
                },
                dailyUsage: (payload.dailyUsage ?? []).compactMap {
                    $0.snapshot(currency: currency)
                },
                modelUsage: (payload.modelStats ?? []).map {
                    $0.snapshot(currency: currency)
                },
                providerStatus: payload.status,
                receivedAt: now()
            )
        } catch let error as ProviderError {
            throw error
        } catch {
            throw ProviderError.invalidResponse
        }
    }
}

private extension APIInfoProvider {
    struct Response: Decodable {
        let isValid: Bool
        let status: String?
        let unit: String?
        let remaining: Decimal?
        let quota: Quota?
        let usage: Usage?
        let dailyUsage: [Daily]?
        let modelStats: [Model]?

        enum CodingKeys: String, CodingKey {
            case isValid
            case status
            case unit
            case remaining
            case quota
            case usage
            case dailyUsage = "daily_usage"
            case modelStats = "model_stats"
        }
    }

    struct Quota: Decodable {
        let limit: Decimal?
        let remaining: Decimal?
        let used: Decimal?
    }

    struct Usage: Decodable {
        let today: Counters?
        let total: Counters?
    }

    struct Counters: Decodable {
        let actualCost: Decimal?
        let requests: Int64?
        let inputTokens: Int64?
        let outputTokens: Int64?
        let cacheReadTokens: Int64?
        let cacheCreationTokens: Int64?
        let totalTokens: Int64?

        enum CodingKeys: String, CodingKey {
            case actualCost = "actual_cost"
            case requests
            case inputTokens = "input_tokens"
            case outputTokens = "output_tokens"
            case cacheReadTokens = "cache_read_tokens"
            case cacheCreationTokens = "cache_creation_tokens"
            case totalTokens = "total_tokens"
        }

        func snapshot(currency: String) -> UsageCounters {
            UsageCounters(
                actualCost: actualCost.map { Money(amount: $0, currency: currency) },
                requests: requests,
                inputTokens: inputTokens,
                outputTokens: outputTokens,
                cacheReadTokens: cacheReadTokens,
                cacheCreationTokens: cacheCreationTokens,
                totalTokens: totalTokens
            )
        }
    }

    struct Daily: Decodable {
        let date: String
        let actualCost: Decimal?
        let requests: Int64?
        let totalTokens: Int64?

        enum CodingKeys: String, CodingKey {
            case date
            case actualCost = "actual_cost"
            case requests
            case totalTokens = "total_tokens"
        }

        func snapshot(currency: String) -> DailyUsage? {
            guard let actualCost else { return nil }
            return DailyUsage(
                date: date,
                actualCost: Money(amount: actualCost, currency: currency),
                requests: requests,
                totalTokens: totalTokens
            )
        }
    }

    struct Model: Decodable {
        let model: String
        let actualCost: Decimal?
        let requests: Int64?
        let totalTokens: Int64?

        enum CodingKeys: String, CodingKey {
            case model
            case actualCost = "actual_cost"
            case requests
            case totalTokens = "total_tokens"
        }

        func snapshot(currency: String) -> ModelUsage {
            ModelUsage(
                model: model,
                actualCost: actualCost.map { Money(amount: $0, currency: currency) },
                requests: requests,
                totalTokens: totalTokens
            )
        }
    }
}
