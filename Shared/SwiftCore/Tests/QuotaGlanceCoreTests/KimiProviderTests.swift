import Foundation
import Testing
@testable import QuotaGlanceCore

@Suite("Kimi provider")
struct KimiProviderTests {
    @Test("China-first detection maps CNY balances without probing internationally")
    func chinaFirstDetectionMapsCNY() async throws {
        let client = KimiSequencedHTTPClient(steps: [
            .response(kimiPayload(available: "12.50", cash: "10", voucher: "2.50"), 200),
        ])
        let provider = try contractProvider(
            provider: "kimi",
            httpClient: client,
            preferredRegion: .china,
            now: { Date(timeIntervalSince1970: 456) }
        )

        let detection = try await provider.detect(apiKey: "redacted-test-key")

        #expect(provider.id == .kimi)
        #expect(
            detection.profile
                == ProviderProfile(region: .china, credentialKind: .standard)
        )
        #expect(
            detection.snapshot.primaryBalance == MonetaryBalance(
                label: "Balance",
                available: Money(
                    amount: Decimal(string: "12.50")!,
                    currency: "CNY"
                ),
                breakdown: [
                    MonetaryValue(
                        label: "Cash",
                        value: Money(amount: 10, currency: "CNY")
                    ),
                    MonetaryValue(
                        label: "Voucher",
                        value: Money(
                            amount: Decimal(string: "2.50")!,
                            currency: "CNY"
                        )
                    ),
                ]
            )
        )
        #expect(detection.snapshot.receivedAt == Date(timeIntervalSince1970: 456))
        #expect(await client.requestedURLs == ["https://api.moonshot.cn/v1/users/me/balance"])
    }

    @Test("Authentication rejection falls back to the other official region")
    func authenticationRejectionFallsBack() async throws {
        let client = KimiSequencedHTTPClient(steps: [
            .response(Data(), 401),
            .response(kimiPayload(available: "8.75", cash: "8", voucher: "0.75"), 200),
        ])
        let provider = try contractProvider(
            provider: "kimi",
            httpClient: client,
            preferredRegion: .china
        )

        let detection = try await provider.detect(apiKey: "redacted-test-key")

        #expect(
            detection.profile
                == ProviderProfile(region: .international, credentialKind: .standard)
        )
        #expect(
            detection.snapshot.primaryBalance?.available
                == Money(amount: Decimal(string: "8.75")!, currency: "USD")
        )
        #expect(await client.requestedURLs == [
            "https://api.moonshot.cn/v1/users/me/balance",
            "https://api.moonshot.ai/v1/users/me/balance",
        ])
    }

    @Test("International preference controls the first probe")
    func internationalPreferenceControlsFirstProbe() async throws {
        let client = KimiSequencedHTTPClient(steps: [
            .response(Data(), 403),
            .response(kimiPayload(available: "20", cash: "15", voucher: "5"), 200),
        ])
        let provider = try contractProvider(
            provider: "kimi",
            httpClient: client,
            preferredRegion: .international
        )

        let detection = try await provider.detect(apiKey: "redacted-test-key")

        #expect(detection.profile.region == .china)
        #expect(detection.snapshot.primaryBalance?.available.currency == "CNY")
        #expect(await client.requestedURLs == [
            "https://api.moonshot.ai/v1/users/me/balance",
            "https://api.moonshot.cn/v1/users/me/balance",
        ])
    }

    @Test("Two regional authentication rejections produce one detection error")
    func twoAuthenticationRejectionsProduceDetectionError() async throws {
        let client = KimiSequencedHTTPClient(steps: [
            .response(Data(), 401),
            .response(Data(), 403),
        ])
        let provider = try contractProvider(
            provider: "kimi",
            httpClient: client,
            preferredRegion: .china
        )

        await #expect(throws: ProviderError.regionDetectionFailed) {
            try await provider.detect(apiKey: "redacted-test-key")
        }
        #expect(await client.requestedURLs.count == 2)
    }

    @Test("Transient provider failures do not probe the other region", arguments: [
        (429, ProviderError.rateLimited),
        (503, ProviderError.httpStatus(503)),
    ])
    func transientFailuresDoNotFallback(statusCode: Int, expected: ProviderError) async throws {
        let client = KimiSequencedHTTPClient(steps: [
            .response(Data(), statusCode),
        ])
        let provider = try contractProvider(
            provider: "kimi",
            httpClient: client,
            preferredRegion: .china
        )

        await #expect(throws: expected) {
            try await provider.detect(apiKey: "redacted-test-key")
        }
        #expect(await client.requestedURLs.count == 1)
    }

    @Test("Transport failures do not probe the other region")
    func transportFailuresDoNotFallback() async throws {
        let client = KimiSequencedHTTPClient(steps: [
            .failure(URLError(.notConnectedToInternet)),
        ])
        let provider = try contractProvider(
            provider: "kimi",
            httpClient: client,
            preferredRegion: .china
        )

        await #expect(throws: URLError.self) {
            try await provider.detect(apiKey: "redacted-test-key")
        }
        #expect(await client.requestedURLs.count == 1)
    }

    @Test("Refresh uses only the persisted region")
    func refreshUsesOnlyPersistedRegion() async throws {
        let client = KimiSequencedHTTPClient(steps: [
            .response(Data(), 401),
        ])
        let provider = try contractProvider(
            provider: "kimi",
            httpClient: client,
            preferredRegion: .china
        )

        await #expect(throws: ProviderError.invalidCredential) {
            try await provider.fetch(
                apiKey: "redacted-test-key",
                profile: ProviderProfile(
                    region: .international,
                    credentialKind: .standard
                )
            )
        }
        #expect(await client.requestedURLs == [
            "https://api.moonshot.ai/v1/users/me/balance",
        ])
    }

    @Test("Requests use bearer authentication and JSON response negotiation")
    func requestsUseExpectedHeaders() async throws {
        let client = KimiSequencedHTTPClient(steps: [
            .response(kimiPayload(available: "1", cash: "1", voucher: "0"), 200),
        ])
        let provider = try contractProvider(
            provider: "kimi",
            httpClient: client,
            preferredRegion: .china
        )

        _ = try await provider.detect(apiKey: "secret")
        let request = try #require(await client.requests.first)

        #expect(request.httpMethod == "GET")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer secret")
        #expect(request.value(forHTTPHeaderField: "Accept") == "application/json")
    }

    @Test("Unsuccessful and malformed payloads are rejected", arguments: [
        #"{"code":1,"status":false}"#,
        #"{"code":0,"status":true}"#,
        #"{"code":0,"status":true,"data":{"available_balance":"bad"}}"#,
    ])
    func unsuccessfulAndMalformedPayloadsAreRejected(payload: String) async throws {
        let client = KimiSequencedHTTPClient(steps: [
            .response(Data(payload.utf8), 200),
        ])
        let provider = try contractProvider(
            provider: "kimi",
            httpClient: client,
            preferredRegion: .china
        )

        await #expect(throws: ProviderError.invalidResponse) {
            try await provider.detect(apiKey: "redacted-test-key")
        }
        #expect(await client.requestedURLs.count == 1)
    }

    @Test("Stored profiles reject unsupported regions and credential kinds")
    func storedProfilesRejectUnsupportedVariants() async throws {
        let client = KimiSequencedHTTPClient(steps: [])
        let provider = try contractProvider(
            provider: "kimi",
            httpClient: client,
            preferredRegion: .china
        )

        await #expect(throws: ProviderError.profileMismatch) {
            try await provider.fetch(
                apiKey: "redacted-test-key",
                profile: ProviderProfile(region: .global, credentialKind: .standard)
            )
        }
        await #expect(throws: ProviderError.profileMismatch) {
            try await provider.fetch(
                apiKey: "redacted-test-key",
                profile: ProviderProfile(region: .china, credentialKind: .management)
            )
        }
        #expect(await client.requestedURLs.isEmpty)
    }
}

private func kimiPayload(available: String, cash: String, voucher: String) -> Data {
    Data(
        """
        {"code":0,"status":true,"data":{"available_balance":"\(available)","cash_balance":"\(cash)","voucher_balance":"\(voucher)"}}
        """.utf8
    )
}

private actor KimiSequencedHTTPClient: HTTPClient {
    enum Step: Sendable {
        case response(Data, Int)
        case failure(URLError)
    }

    private var steps: [Step]
    private(set) var requests: [URLRequest] = []

    var requestedURLs: [String] {
        requests.compactMap { $0.url?.absoluteString }
    }

    init(steps: [Step]) {
        self.steps = steps
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        let step = steps.removeFirst()
        switch step {
        case let .response(data, statusCode):
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: statusCode,
                httpVersion: "HTTP/1.1",
                headerFields: nil
            )!
            return (data, response)
        case let .failure(error):
            throw error
        }
    }
}
