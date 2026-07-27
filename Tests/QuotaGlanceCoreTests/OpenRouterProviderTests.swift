import Foundation
import Testing
@testable import QuotaGlanceCore

@Suite("OpenRouter provider")
struct OpenRouterProviderTests {
    @Test("A capped standard key exposes spend and a non-balance key limit")
    func cappedStandardKeyExposesSpendAndLimit() async throws {
        let client = OpenRouterSequencedHTTPClient(steps: [
            .response(openRouterKeyPayload(
                isManagement: false,
                usage: "25.5",
                limit: "100",
                limitRemaining: "74.5",
                daily: "1.25",
                weekly: "3.5",
                monthly: "10"
            ), 200),
        ])
        let provider = OpenRouterProvider(
            httpClient: client,
            now: { Date(timeIntervalSince1970: 789) }
        )

        let detection = try await provider.detect(apiKey: "redacted-test-key")

        #expect(provider.id == .openRouter)
        #expect(
            detection.profile
                == ProviderProfile(region: .global, credentialKind: .standard)
        )
        #expect(detection.snapshot.balances.isEmpty)
        #expect(
            detection.snapshot.spendingLimit == SpendingLimit(
                label: "Key limit",
                used: Money(amount: Decimal(string: "25.5")!, currency: "USD"),
                limit: Money(amount: 100, currency: "USD"),
                remaining: Money(amount: Decimal(string: "74.5")!, currency: "USD")
            )
        )
        #expect(
            detection.snapshot.spend == SpendSummary(
                today: Money(amount: Decimal(string: "1.25")!, currency: "USD"),
                week: Money(amount: Decimal(string: "3.5")!, currency: "USD"),
                month: Money(amount: 10, currency: "USD"),
                total: Money(amount: Decimal(string: "25.5")!, currency: "USD")
            )
        )
        #expect(detection.snapshot.receivedAt == Date(timeIntervalSince1970: 789))
        #expect(await client.requestedURLs == ["https://openrouter.ai/api/v1/key"])
    }

    @Test("An uncapped standard key exposes spend without inventing a limit")
    func uncappedStandardKeyExposesOnlySpend() async throws {
        let data = Data(
            #"{"data":{"is_management_key":false,"usage":4,"usage_daily":1,"usage_weekly":2,"usage_monthly":3,"limit":null,"limit_remaining":null,"rate_limit":{"requests":999999}}}"#.utf8
        )
        let client = OpenRouterSequencedHTTPClient(steps: [.response(data, 200)])
        let provider = OpenRouterProvider(httpClient: client)

        let detection = try await provider.detect(apiKey: "redacted-test-key")

        #expect(detection.profile.credentialKind == .standard)
        #expect(detection.snapshot.spendingLimit == nil)
        #expect(detection.snapshot.spend.total == Money(amount: 4, currency: "USD"))
        #expect(detection.snapshot.balances.isEmpty)
        #expect(await client.requestedURLs.count == 1)
    }

    @Test("A management key adds account credits as a real balance")
    func managementKeyAddsAccountCreditsBalance() async throws {
        let client = OpenRouterSequencedHTTPClient(steps: [
            .response(openRouterKeyPayload(
                isManagement: true,
                usage: "5",
                limit: nil,
                limitRemaining: nil,
                daily: "1",
                weekly: "2",
                monthly: "4"
            ), 200),
            .response(Data(#"{"data":{"total_credits":100,"total_usage":25.25}}"#.utf8), 200),
        ])
        let provider = OpenRouterProvider(httpClient: client)

        let detection = try await provider.detect(apiKey: "redacted-management-key")

        #expect(detection.profile.credentialKind == .management)
        #expect(
            detection.snapshot.primaryBalance?.available
                == Money(amount: Decimal(string: "74.75")!, currency: "USD")
        )
        #expect(detection.snapshot.spend.total == Money(amount: 5, currency: "USD"))
        #expect(await client.requestedURLs == [
            "https://openrouter.ai/api/v1/key",
            "https://openrouter.ai/api/v1/credits",
        ])
    }

    @Test("A negative management credit balance is preserved")
    func negativeManagementBalanceIsPreserved() async throws {
        let client = OpenRouterSequencedHTTPClient(steps: [
            .response(openRouterKeyPayload(
                isManagement: true,
                usage: "0",
                limit: nil,
                limitRemaining: nil,
                daily: nil,
                weekly: nil,
                monthly: nil
            ), 200),
            .response(Data(#"{"data":{"total_credits":"10","total_usage":"12.5"}}"#.utf8), 200),
        ])
        let provider = OpenRouterProvider(httpClient: client)

        let detection = try await provider.detect(apiKey: "redacted-management-key")

        #expect(
            detection.snapshot.primaryBalance?.available
                == Money(amount: Decimal(string: "-2.5")!, currency: "USD")
        )
    }

    @Test("Stored profiles require the observed credential kind")
    func storedProfilesRequireObservedKind() async {
        let client = OpenRouterSequencedHTTPClient(steps: [
            .response(openRouterKeyPayload(
                isManagement: true,
                usage: "0",
                limit: nil,
                limitRemaining: nil,
                daily: nil,
                weekly: nil,
                monthly: nil
            ), 200),
        ])
        let provider = OpenRouterProvider(httpClient: client)

        await #expect(throws: ProviderError.profileMismatch) {
            try await provider.fetch(
                apiKey: "redacted-test-key",
                profile: ProviderProfile(region: .global, credentialKind: .standard)
            )
        }
        #expect(await client.requestedURLs == ["https://openrouter.ai/api/v1/key"])
    }

    @Test("Unsupported profile regions are rejected before requests")
    func unsupportedProfileRegionsAreRejected() async {
        let client = OpenRouterSequencedHTTPClient(steps: [])
        let provider = OpenRouterProvider(httpClient: client)

        await #expect(throws: ProviderError.profileMismatch) {
            try await provider.fetch(
                apiKey: "redacted-test-key",
                profile: ProviderProfile(region: .china, credentialKind: .standard)
            )
        }
        #expect(await client.requestedURLs.isEmpty)
    }

    @Test("Requests use the official endpoints and bearer authentication")
    func requestsUseOfficialEndpointsAndHeaders() async throws {
        let client = OpenRouterSequencedHTTPClient(steps: [
            .response(openRouterKeyPayload(
                isManagement: true,
                usage: "0",
                limit: nil,
                limitRemaining: nil,
                daily: nil,
                weekly: nil,
                monthly: nil
            ), 200),
            .response(Data(#"{"data":{"total_credits":1,"total_usage":0}}"#.utf8), 200),
        ])
        let provider = OpenRouterProvider(httpClient: client)

        _ = try await provider.detect(apiKey: "secret")
        let requests = await client.requests

        #expect(requests.count == 2)
        #expect(requests.allSatisfy { $0.httpMethod == "GET" })
        #expect(requests.allSatisfy {
            $0.value(forHTTPHeaderField: "Authorization") == "Bearer secret"
        })
        #expect(requests.allSatisfy {
            $0.value(forHTTPHeaderField: "Accept") == "application/json"
        })
    }

    @Test("HTTP errors from either endpoint remain typed")
    func httpErrorsRemainTyped() async {
        let keyFailureClient = OpenRouterSequencedHTTPClient(steps: [
            .response(Data(), 429),
        ])
        await #expect(throws: ProviderError.rateLimited) {
            try await OpenRouterProvider(httpClient: keyFailureClient)
                .detect(apiKey: "redacted-test-key")
        }

        let creditsFailureClient = OpenRouterSequencedHTTPClient(steps: [
            .response(openRouterKeyPayload(
                isManagement: true,
                usage: "0",
                limit: nil,
                limitRemaining: nil,
                daily: nil,
                weekly: nil,
                monthly: nil
            ), 200),
            .response(Data(), 403),
        ])
        await #expect(throws: ProviderError.invalidCredential) {
            try await OpenRouterProvider(httpClient: creditsFailureClient)
                .detect(apiKey: "redacted-management-key")
        }
    }

    @Test("Malformed key and credits payloads are rejected")
    func malformedPayloadsAreRejected() async {
        let malformedKeyClient = OpenRouterSequencedHTTPClient(steps: [
            .response(Data(#"{"data":{"usage":1}}"#.utf8), 200),
        ])
        await #expect(throws: ProviderError.invalidResponse) {
            try await OpenRouterProvider(httpClient: malformedKeyClient)
                .detect(apiKey: "redacted-test-key")
        }

        let malformedCreditsClient = OpenRouterSequencedHTTPClient(steps: [
            .response(openRouterKeyPayload(
                isManagement: true,
                usage: "0",
                limit: nil,
                limitRemaining: nil,
                daily: nil,
                weekly: nil,
                monthly: nil
            ), 200),
            .response(Data(#"{"data":{"total_credits":10}}"#.utf8), 200),
        ])
        await #expect(throws: ProviderError.invalidResponse) {
            try await OpenRouterProvider(httpClient: malformedCreditsClient)
                .detect(apiKey: "redacted-management-key")
        }
    }
}

private func openRouterKeyPayload(
    isManagement: Bool,
    usage: String,
    limit: String?,
    limitRemaining: String?,
    daily: String?,
    weekly: String?,
    monthly: String?
) -> Data {
    func value(_ value: String?) -> String {
        value.map { "\"\($0)\"" } ?? "null"
    }

    return Data(
        """
        {"data":{"is_management_key":\(isManagement),"usage":"\(usage)","limit":\(value(limit)),"limit_remaining":\(value(limitRemaining)),"usage_daily":\(value(daily)),"usage_weekly":\(value(weekly)),"usage_monthly":\(value(monthly))}}
        """.utf8
    )
}

private actor OpenRouterSequencedHTTPClient: HTTPClient {
    enum Step: Sendable {
        case response(Data, Int)
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
        }
    }
}
