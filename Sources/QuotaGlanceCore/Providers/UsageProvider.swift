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

public protocol UsageProvider: Sendable {
    func fetch(apiKey: String) async throws -> ProviderUsageSnapshot
}

public enum ProviderError: Error, Equatable, Sendable {
    case invalidCredential
    case rateLimited
    case httpStatus(Int)
    case invalidResponse
    case providerInactive
}
