import Foundation
import Testing
@testable import QuotaGlanceCore

@Suite("API Info provider")
struct APIInfoProviderTests {
    @Test("Top-level remaining is authoritative")
    func topLevelRemainingIsAuthoritative() async throws {
        let provider = APIInfoProvider(
            httpClient: StubHTTPClient(
                data: try Fixture.data(named: "api-info-complete"),
                statusCode: 200
            ),
            now: { Date(timeIntervalSince1970: 100) }
        )

        let snapshot = try await provider.fetch(apiKey: "redacted-test-key")

        let remaining = try #require(snapshot.remaining)
        #expect(remaining.amount == Decimal(string: "544.045471"))
        #expect(
            remaining.amount
                != snapshot.quotaLimit!.amount - snapshot.quotaUsed!.amount
        )
        #expect(snapshot.receivedAt == Date(timeIntervalSince1970: 100))
    }

    @Test("Request uses the documented endpoint and headers")
    func requestUsesDocumentedEndpointAndHeaders() async throws {
        let client = RecordingHTTPClient(
            data: try Fixture.data(named: "api-info-complete"),
            statusCode: 200
        )

        _ = try await APIInfoProvider(httpClient: client).fetch(apiKey: "secret")
        let request = await client.lastRequest

        #expect(request?.url?.absoluteString == "https://www.api-info.net/v1/usage")
        #expect(request?.httpMethod == "GET")
        #expect(request?.value(forHTTPHeaderField: "Authorization") == "Bearer secret")
        #expect(request?.value(forHTTPHeaderField: "Accept") == "application/json")
    }

    @Test("HTTP 401 and 403 identify invalid credentials", arguments: [401, 403])
    func authenticationFailuresAreTyped(statusCode: Int) async throws {
        let provider = APIInfoProvider(
            httpClient: StubHTTPClient(data: Data(), statusCode: statusCode)
        )

        await #expect(throws: ProviderError.invalidCredential) {
            try await provider.fetch(apiKey: "redacted-test-key")
        }
    }

    @Test("HTTP 429 identifies rate limiting")
    func rateLimitFailureIsTyped() async throws {
        let provider = APIInfoProvider(
            httpClient: StubHTTPClient(data: Data(), statusCode: 429)
        )

        await #expect(throws: ProviderError.rateLimited) {
            try await provider.fetch(apiKey: "redacted-test-key")
        }
    }

    @Test("Other HTTP failures preserve their status code")
    func otherHTTPFailurePreservesStatusCode() async throws {
        let provider = APIInfoProvider(
            httpClient: StubHTTPClient(data: Data(), statusCode: 503)
        )

        await #expect(throws: ProviderError.httpStatus(503)) {
            try await provider.fetch(apiKey: "redacted-test-key")
        }
    }

    @Test("An invalid provider payload is rejected")
    func invalidProviderPayloadIsRejected() async throws {
        let data = Data(
            #"{"isValid":false,"status":"inactive"}"#.utf8
        )
        let provider = APIInfoProvider(
            httpClient: StubHTTPClient(data: data, statusCode: 200)
        )

        await #expect(throws: ProviderError.providerInactive) {
            try await provider.fetch(apiKey: "redacted-test-key")
        }
    }

    @Test("A complete response maps all supported usage metrics")
    func completeResponseMapsSupportedMetrics() async throws {
        let provider = APIInfoProvider(
            httpClient: StubHTTPClient(
                data: try Fixture.data(named: "api-info-complete"),
                statusCode: 200
            ),
            now: { Date(timeIntervalSince1970: 100) }
        )

        let snapshot = try await provider.fetch(apiKey: "redacted-test-key")

        #expect(snapshot.providerStatus == "active")
        #expect(snapshot.quotaLimit == Money(amount: 7200, currency: "USD"))
        #expect(snapshot.quotaUsed == Money(amount: Decimal(string: "6655.90")!, currency: "USD"))
        #expect(
            snapshot.today == UsageCounters(
                actualCost: Money(amount: Decimal(string: "12.34")!, currency: "USD"),
                requests: 42,
                inputTokens: 1_000,
                outputTokens: 50,
                cacheReadTokens: 5_000,
                cacheCreationTokens: 0,
                totalTokens: 6_050
            )
        )
        #expect(snapshot.total?.requests == 37_194)
        #expect(snapshot.total?.totalTokens == 5_424_197_397)
        #expect(
            snapshot.dailyUsage == [
                DailyUsage(
                    date: "2026-07-22",
                    actualCost: Money(amount: Decimal(string: "12.34")!, currency: "USD"),
                    requests: 42,
                    totalTokens: 6_050
                )
            ]
        )
        #expect(
            snapshot.modelUsage == [
                ModelUsage(
                    model: "gpt-test",
                    actualCost: Money(amount: 10, currency: "USD"),
                    requests: 40,
                    totalTokens: 6_000
                )
            ]
        )
    }

    @Test("A valid response without currency is rejected")
    func missingCurrencyIsRejected() async throws {
        let data = Data(#"{"isValid":true,"remaining":10}"#.utf8)
        let provider = APIInfoProvider(
            httpClient: StubHTTPClient(data: data, statusCode: 200)
        )

        await #expect(throws: ProviderError.invalidResponse) {
            try await provider.fetch(apiKey: "redacted-test-key")
        }
    }

    @Test("Optional usage sections may be absent")
    func optionalUsageSectionsMayBeAbsent() async throws {
        let data = Data(
            #"{"isValid":true,"remaining":10.25,"unit":"USD"}"#.utf8
        )
        let provider = APIInfoProvider(
            httpClient: StubHTTPClient(data: data, statusCode: 200)
        )

        let snapshot = try await provider.fetch(apiKey: "redacted-test-key")

        #expect(snapshot.remaining == Money(amount: Decimal(string: "10.25")!, currency: "USD"))
        #expect(snapshot.quotaLimit == nil)
        #expect(snapshot.quotaUsed == nil)
        #expect(snapshot.today == nil)
        #expect(snapshot.total == nil)
        #expect(snapshot.dailyUsage.isEmpty)
        #expect(snapshot.modelUsage.isEmpty)
    }
}

private struct StubHTTPClient: HTTPClient {
    let data: Data
    let statusCode: Int

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: nil
        )!
        return (data, response)
    }
}

private actor RecordingHTTPClient: HTTPClient {
    let data: Data
    let statusCode: Int
    private(set) var lastRequest: URLRequest?

    init(data: Data, statusCode: Int) {
        self.data = data
        self.statusCode = statusCode
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        lastRequest = request
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: nil
        )!
        return (data, response)
    }
}

private enum Fixture {
    static func data(named name: String) throws -> Data {
        let url = try #require(
            Bundle.module.url(forResource: name, withExtension: "json")
        )
        return try Data(contentsOf: url)
    }
}
