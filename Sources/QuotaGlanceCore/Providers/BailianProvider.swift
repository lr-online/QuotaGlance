import Foundation

public struct BailianProvider: UsageProvider {
    public let id = ProviderID.bailian

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
        try await detect(apiKey: apiKey, configuration: nil)
    }

    public func detect(
        apiKey: String,
        configuration: ProviderConfiguration?
    ) async throws -> ProviderDetection {
        let baseURL = try normalizedBaseURL(configuration)
        let profile = ProviderProfile(
            region: try BailianEndpoint.region(for: baseURL),
            credentialKind: .standard
        )
        return ProviderDetection(
            profile: profile,
            snapshot: try await requestModels(apiKey: apiKey, baseURL: baseURL)
        )
    }

    public func fetch(apiKey: String) async throws -> ProviderUsageSnapshot {
        try await requestModels(
            apiKey: apiKey,
            baseURL: BailianEndpoint.defaultBaseURL
        )
    }

    public func fetch(
        apiKey: String,
        profile: ProviderProfile
    ) async throws -> ProviderUsageSnapshot {
        try await fetch(apiKey: apiKey, profile: profile, configuration: nil)
    }

    public func fetch(
        apiKey: String,
        profile: ProviderProfile,
        configuration: ProviderConfiguration?
    ) async throws -> ProviderUsageSnapshot {
        let baseURL = try normalizedBaseURL(configuration)
        let expectedProfile = ProviderProfile(
            region: try BailianEndpoint.region(for: baseURL),
            credentialKind: .standard
        )
        guard profile == expectedProfile else {
            throw ProviderError.profileMismatch
        }
        return try await requestModels(apiKey: apiKey, baseURL: baseURL)
    }
}

private extension BailianProvider {
    func normalizedBaseURL(
        _ configuration: ProviderConfiguration?
    ) throws -> URL {
        try BailianEndpoint.normalizedBaseURL(
            from: configuration?.baseURL.absoluteString ?? ""
        )
    }

    func requestModels(
        apiKey: String,
        baseURL: URL
    ) async throws -> ProviderUsageSnapshot {
        var request = URLRequest(
            url: baseURL.appendingPathComponent("models", isDirectory: false)
        )
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
                metricsUnavailableReason: "\(identifiers.count) models available. Billing metrics unavailable for this API key.",
                receivedAt: now()
            )
        } catch let error as ProviderError {
            throw error
        } catch {
            throw ProviderError.invalidResponse
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
