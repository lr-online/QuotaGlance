import Foundation
import Testing
@testable import QuotaGlanceCore

@Suite("BioMap Coding provider")
struct BioMapCodingProviderTests {
    @Test("Key info maps cumulative spend and budget without a cash balance")
    func keyInfoMapsSpendAndBudget() async throws {
        let client = BioMapRecordingHTTPClient(steps: [
            .response(
                Data(
                    #"{"key":"sk-echoed-value","info":{"spend":12.345678,"max_budget":"50.00","budget_duration":"30d","blocked":false,"models":["claude-sonnet"]}}"#.utf8
                ),
                200
            ),
        ])
        let provider = BioMapCodingProvider(
            httpClient: client,
            now: { Date(timeIntervalSince1970: 123) }
        )

        let detection = try await provider.detect(apiKey: "secret")
        let request = try #require(await client.requests.first)

        #expect(provider.id == .bioMapCoding)
        #expect(
            detection.profile
                == ProviderProfile(region: .global, credentialKind: .standard)
        )
        #expect(detection.snapshot.balances.isEmpty)
        #expect(
            detection.snapshot.spend.total
                == usd("12.345678")
        )
        #expect(
            detection.snapshot.spendingLimit
                == SpendingLimit(
                    label: "Key budget",
                    used: usd("12.345678"),
                    limit: usd("50.00"),
                    remaining: usd("37.654322"),
                    resetDescription: "Budget period: 30d"
                )
        )
        #expect(detection.snapshot.providerStatus == "active")
        #expect(detection.snapshot.metricsUnavailableReason == nil)
        #expect(detection.snapshot.receivedAt == Date(timeIntervalSince1970: 123))
        #expect(request.url == BioMapCodingProvider.keyInfoEndpoint)
        #expect(request.url?.query == nil)
        #expect(request.httpMethod == "GET")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer secret")
        #expect(request.value(forHTTPHeaderField: "Accept") == "application/json")
    }

    @Test("A key without quantitative fields remains a clear connection snapshot")
    func missingMetricsRemainAbsent() async throws {
        let provider = BioMapCodingProvider(
            httpClient: BioMapRecordingHTTPClient(steps: [
                .response(
                    Data(
                        #"{"key":"ignored","info":{"spend":null,"max_budget":null,"blocked":false}}"#.utf8
                    ),
                    200
                ),
            ])
        )

        let snapshot = try await provider.fetch(apiKey: "redacted-test-key")

        #expect(snapshot.balances.isEmpty)
        #expect(snapshot.spendingLimit == nil)
        #expect(snapshot.spend.isEmpty)
        #expect(
            snapshot.metricsUnavailableReason
                == "Budget metrics unavailable for this key."
        )
    }

    @Test("A blocked virtual key is inactive")
    func blockedKeyIsInactive() async {
        let provider = BioMapCodingProvider(
            httpClient: BioMapRecordingHTTPClient(steps: [
                .response(
                    Data(
                        #"{"key":"ignored","info":{"spend":1,"max_budget":10,"blocked":true}}"#.utf8
                    ),
                    200
                ),
            ])
        )

        await #expect(throws: ProviderError.providerInactive) {
            try await provider.detect(apiKey: "redacted-test-key")
        }
    }

    @Test("Authentication, rate-limit, and server failures stay typed", arguments: [
        (401, ProviderError.invalidCredential),
        (429, ProviderError.rateLimited),
        (503, ProviderError.httpStatus(503)),
    ])
    func httpFailuresStayTyped(statusCode: Int, expected: ProviderError) async {
        let provider = BioMapCodingProvider(
            httpClient: BioMapRecordingHTTPClient(steps: [
                .response(Data(), statusCode),
            ])
        )

        await #expect(throws: expected) {
            try await provider.detect(apiKey: "redacted-test-key")
        }
    }

    @Test("Malformed key info is rejected", arguments: [
        #"{}"#,
        #"{"info":null}"#,
        #"{"info":{"spend":"bad","max_budget":10}}"#,
        #"{"info":{"spend":1,"max_budget":-1}}"#,
    ])
    func malformedKeyInfoIsRejected(payload: String) async {
        let provider = BioMapCodingProvider(
            httpClient: BioMapRecordingHTTPClient(steps: [
                .response(Data(payload.utf8), 200),
            ])
        )

        await #expect(throws: ProviderError.invalidResponse) {
            try await provider.detect(apiKey: "redacted-test-key")
        }
    }

    @Test("Stored profiles must stay global standard keys")
    func storedProfileMustMatch() async {
        let provider = BioMapCodingProvider(
            httpClient: BioMapRecordingHTTPClient(steps: [])
        )

        await #expect(throws: ProviderError.profileMismatch) {
            try await provider.fetch(
                apiKey: "redacted-test-key",
                profile: ProviderProfile(
                    region: .china,
                    credentialKind: .standard
                )
            )
        }
    }

    @Test("Restricted key-info routes fall back to the model list", arguments: [
        403,
        404,
        405,
    ])
    func restrictedKeyInfoFallsBack(statusCode: Int) async throws {
        let client = BioMapRecordingHTTPClient(steps: [
            .response(Data(), statusCode),
            .response(
                Data(
                    #"{"object":"list","data":[{"id":"claude-sonnet"},{"id":"gemini-pro"}]}"#.utf8
                ),
                200
            ),
        ])
        let provider = BioMapCodingProvider(
            httpClient: client,
            now: { Date(timeIntervalSince1970: 456) }
        )

        let snapshot = try await provider.fetch(apiKey: "secret")
        let requests = await client.requests

        #expect(requests.map(\.url) == [
            BioMapCodingProvider.keyInfoEndpoint,
            BioMapCodingProvider.modelsEndpoint,
        ])
        #expect(
            requests.allSatisfy {
                $0.value(forHTTPHeaderField: "Authorization") == "Bearer secret"
            }
        )
        #expect(snapshot.providerStatus == "connected")
        #expect(
            snapshot.metricsUnavailableReason
                == "2 models available. Budget metrics unavailable for this key."
        )
        #expect(snapshot.receivedAt == Date(timeIntervalSince1970: 456))
        #expect(snapshot.balances.isEmpty)
        #expect(snapshot.spend.isEmpty)
    }

    @Test("Authentication, rate limiting, and server errors never fall back", arguments: [
        (401, ProviderError.invalidCredential),
        (429, ProviderError.rateLimited),
        (503, ProviderError.httpStatus(503)),
    ])
    func otherErrorsDoNotFallBack(statusCode: Int, expected: ProviderError) async {
        let client = BioMapRecordingHTTPClient(steps: [
            .response(Data(), statusCode),
        ])
        let provider = BioMapCodingProvider(httpClient: client)

        await #expect(throws: expected) {
            try await provider.fetch(apiKey: "redacted-test-key")
        }
        #expect(await client.requests.count == 1)
    }

    @Test("Malformed fallback model lists are rejected", arguments: [
        #"{}"#,
        #"{"object":"list","data":[]}"#,
        #"{"object":"list","data":[{"id":""}]}"#,
    ])
    func malformedFallbackModelListIsRejected(payload: String) async {
        let provider = BioMapCodingProvider(
            httpClient: BioMapRecordingHTTPClient(steps: [
                .response(Data(), 403),
                .response(Data(payload.utf8), 200),
            ])
        )

        await #expect(throws: ProviderError.invalidResponse) {
            try await provider.fetch(apiKey: "redacted-test-key")
        }
    }
}

private func usd(_ value: String) -> Money {
    Money(amount: Decimal(string: value)!, currency: "USD")
}

private actor BioMapRecordingHTTPClient: HTTPClient {
    enum Step: Sendable {
        case response(Data, Int)
    }

    private var steps: [Step]
    private(set) var requests: [URLRequest] = []

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
        }
    }
}
