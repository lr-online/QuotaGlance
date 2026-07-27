import Foundation

public protocol HTTPClient: Sendable {
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

public struct URLSessionHTTPClient: HTTPClient {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else {
            throw ProviderError.invalidResponse
        }
        return (data, response)
    }
}

public struct ProviderDetection: Equatable, Sendable {
    public var profile: ProviderProfile
    public var snapshot: ProviderUsageSnapshot

    public init(profile: ProviderProfile, snapshot: ProviderUsageSnapshot) {
        self.profile = profile
        self.snapshot = snapshot
    }
}

public protocol UsageProvider: Sendable {
    var id: ProviderID { get }
    func fetch(apiKey: String) async throws -> ProviderUsageSnapshot
    func detect(apiKey: String) async throws -> ProviderDetection
    func detect(
        apiKey: String,
        configuration: ProviderConfiguration?
    ) async throws -> ProviderDetection
    func fetch(
        apiKey: String,
        profile: ProviderProfile
    ) async throws -> ProviderUsageSnapshot
    func fetch(
        apiKey: String,
        profile: ProviderProfile,
        configuration: ProviderConfiguration?
    ) async throws -> ProviderUsageSnapshot
}

public extension UsageProvider {
    var id: ProviderID { .apiInfo }

    func detect(apiKey: String) async throws -> ProviderDetection {
        ProviderDetection(
            profile: .apiInfo,
            snapshot: try await fetch(apiKey: apiKey)
        )
    }

    func detect(
        apiKey: String,
        configuration: ProviderConfiguration?
    ) async throws -> ProviderDetection {
        try await detect(apiKey: apiKey)
    }

    func fetch(
        apiKey: String,
        profile: ProviderProfile
    ) async throws -> ProviderUsageSnapshot {
        try await fetch(apiKey: apiKey)
    }

    func fetch(
        apiKey: String,
        profile: ProviderProfile,
        configuration: ProviderConfiguration?
    ) async throws -> ProviderUsageSnapshot {
        try await fetch(apiKey: apiKey, profile: profile)
    }
}

public struct ProviderRegistry: Sendable {
    private let providers: [ProviderID: any UsageProvider]

    public init(providers: [any UsageProvider]) {
        var values: [ProviderID: any UsageProvider] = [:]
        for provider in providers {
            values[provider.id] = provider
        }
        self.providers = values
    }

    public func provider(for id: ProviderID) throws -> any UsageProvider {
        guard let provider = providers[id] else {
            throw ProviderError.providerUnavailable(id)
        }
        return provider
    }
}

public enum ProviderError: Error, Equatable, Sendable {
    case invalidCredential
    case rateLimited
    case httpStatus(Int)
    case invalidResponse
    case providerInactive
    case unsupportedCredential
    case regionDetectionFailed
    case profileMismatch
    case invalidEndpoint
    case providerUnavailable(ProviderID)
}

enum ProviderHTTPStatus {
    static func validate(_ response: HTTPURLResponse) throws {
        switch response.statusCode {
        case 200..<300:
            return
        case 401, 403:
            throw ProviderError.invalidCredential
        case 429:
            throw ProviderError.rateLimited
        default:
            throw ProviderError.httpStatus(response.statusCode)
        }
    }
}

struct ProviderDecimal: Decodable, Equatable, Sendable {
    let value: Decimal

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let decimal = try? container.decode(Decimal.self) {
            value = decimal
            return
        }
        if let string = try? container.decode(String.self),
           let decimal = Decimal(
               string: string,
               locale: Locale(identifier: "en_US_POSIX")
           ) {
            value = decimal
            return
        }
        throw DecodingError.dataCorruptedError(
            in: container,
            debugDescription: "Expected a decimal number or numeric string."
        )
    }
}
