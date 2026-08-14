import Foundation
import Testing
@testable import QuotaGlanceCore

@Suite("MiniMax provider")
struct MiniMaxProviderTests {
    @Test("Pay-as-you-go keys are rejected before any regional probe")
    func payAsYouGoKeysAreRejectedImmediately() async throws {
        let client = MiniMaxSequencedHTTPClient(steps: [])
        let provider = try contractProvider(
            provider: "minimax",
            httpClient: client,
            preferredRegion: .china
        )

        await #expect(throws: ProviderError.unsupportedCredential) {
            try await provider.detect(apiKey: "  sk-api-redacted  ")
        }
        #expect(await client.requestedURLs.isEmpty)
    }

    @Test("China detection maps direct quota values without monetary balances")
    func chinaDetectionMapsDirectQuotaValues() async throws {
        let payload = Data(
            #"{"model_remains":[{"model_name":"MiniMax-M2","remains":"900","total":1000,"reset_time":1800000000,"unit":"requests"}],"base_resp":{"status_code":0,"status_msg":"success"}}"#.utf8
        )
        let client = MiniMaxSequencedHTTPClient(steps: [.response(payload, 200)])
        let provider = try contractProvider(
            provider: "minimax",
            httpClient: client,
            preferredRegion: .china,
            now: { Date(timeIntervalSince1970: 321) }
        )

        let detection = try await provider.detect(apiKey: "redacted-plan-key")

        #expect(provider.id == .miniMax)
        #expect(
            detection.profile
                == ProviderProfile(region: .china, credentialKind: .tokenPlan)
        )
        #expect(detection.snapshot.balances.isEmpty)
        #expect(
            detection.snapshot.quotaWindows == [
                QuotaWindow(
                    label: "MiniMax-M2 quota",
                    used: 100,
                    limit: 1000,
                    remaining: 900,
                    unit: "requests",
                    resetsAt: Date(timeIntervalSince1970: 1_800_000_000)
                )
            ]
        )
        #expect(detection.snapshot.receivedAt == Date(timeIntervalSince1970: 321))
        #expect(await client.requestedURLs == [
            "https://www.minimaxi.com/v1/token_plan/remains",
        ])
    }

    @Test("Current interval and weekly fields map to separate quota windows")
    func intervalAndWeeklyFieldsMapToQuotaWindows() async throws {
        let payload = Data(
            """
            {"model_remains":[{"model_name":"general","start_time":1800000000000,"end_time":1800018000000,"current_interval_total_count":"1000","current_interval_usage_count":100,"current_interval_status":1,"current_weekly_total_count":2000,"current_weekly_usage_count":"400","current_weekly_status":1,"weekly_end_time":1800604800000}],"base_resp":{"status_code":"0"}}
            """.utf8
        )
        let client = MiniMaxSequencedHTTPClient(steps: [.response(payload, 200)])
        let provider = try contractProvider(
            provider: "minimax",
            httpClient: client,
            preferredRegion: .international
        )

        let detection = try await provider.detect(apiKey: "redacted-plan-key")

        #expect(detection.profile.region == .international)
        #expect(detection.snapshot.quotaWindows.count == 2)
        #expect(
            detection.snapshot.quotaWindows[0] == QuotaWindow(
                label: "general 5-hour quota",
                used: 100,
                limit: 1000,
                remaining: 900,
                unit: "requests",
                resetsAt: Date(timeIntervalSince1970: 1_800_018_000)
            )
        )
        #expect(
            detection.snapshot.quotaWindows[1] == QuotaWindow(
                label: "general weekly quota",
                used: 400,
                limit: 2000,
                remaining: 1600,
                unit: "requests",
                resetsAt: Date(timeIntervalSince1970: 1_800_604_800)
            )
        )
    }

    @Test("Remaining percentages map without inventing request counts")
    func remainingPercentagesMapAsPercentWindows() async throws {
        let payload = Data(
            #"{"model_remains":[{"model_name":"general","end_time":1800018000000,"current_interval_status":1,"current_interval_remaining_percent":"98","current_weekly_status":1,"current_weekly_remaining_percent":67,"weekly_end_time":1800604800000}],"base_resp":{"status_code":0}}"#.utf8
        )
        let client = MiniMaxSequencedHTTPClient(steps: [.response(payload, 200)])
        let provider = try contractProvider(
            provider: "minimax",
            httpClient: client,
            preferredRegion: .international
        )

        let snapshot = try await provider.detect(apiKey: "redacted-plan-key").snapshot

        #expect(snapshot.quotaWindows[0].used == 2)
        #expect(snapshot.quotaWindows[0].limit == 100)
        #expect(snapshot.quotaWindows[0].remaining == 98)
        #expect(snapshot.quotaWindows[0].unit == "%")
        #expect(snapshot.quotaWindows[1].used == 33)
        #expect(snapshot.quotaWindows[1].remaining == 67)
    }

    @Test("Authentication rejection falls back to the other region")
    func authenticationRejectionFallsBack() async throws {
        let client = MiniMaxSequencedHTTPClient(steps: [
            .response(Data(), 401),
            .response(miniMaxQuotaPayload(), 200),
        ])
        let provider = try contractProvider(
            provider: "minimax",
            httpClient: client,
            preferredRegion: .china
        )

        let detection = try await provider.detect(apiKey: "redacted-plan-key")

        #expect(detection.profile.region == .international)
        #expect(await client.requestedURLs == [
            "https://www.minimaxi.com/v1/token_plan/remains",
            "https://www.minimax.io/v1/token_plan/remains",
        ])
    }

    @Test("Embedded authentication rejection also falls back")
    func embeddedAuthenticationRejectionFallsBack() async throws {
        let client = MiniMaxSequencedHTTPClient(steps: [
            .response(Data(#"{"base_resp":{"status_code":1004,"status_msg":"invalid api key"}}"#.utf8), 200),
            .response(miniMaxQuotaPayload(), 200),
        ])
        let provider = try contractProvider(
            provider: "minimax",
            httpClient: client,
            preferredRegion: .international
        )

        let detection = try await provider.detect(apiKey: "redacted-plan-key")

        #expect(detection.profile.region == .china)
        #expect(await client.requestedURLs.count == 2)
    }

    @Test("Two regional authentication rejections produce a detection error")
    func twoAuthenticationRejectionsProduceDetectionError() async throws {
        let client = MiniMaxSequencedHTTPClient(steps: [
            .response(Data(), 403),
            .response(Data(#"{"base_resp":{"status_code":"1004"}}"#.utf8), 200),
        ])
        let provider = try contractProvider(
            provider: "minimax",
            httpClient: client,
            preferredRegion: .china
        )

        await #expect(throws: ProviderError.regionDetectionFailed) {
            try await provider.detect(apiKey: "redacted-plan-key")
        }
        #expect(await client.requestedURLs.count == 2)
    }

    @Test("Transient and embedded provider failures do not probe another region")
    func transientAndEmbeddedFailuresDoNotFallback() async throws {
        let rateLimitClient = MiniMaxSequencedHTTPClient(steps: [
            .response(Data(), 429),
        ])
        await #expect(throws: ProviderError.rateLimited) {
            try await contractProvider(
                provider: "minimax",
                httpClient: rateLimitClient,
                preferredRegion: .china
            ).detect(apiKey: "redacted-plan-key")
        }
        #expect(await rateLimitClient.requestedURLs.count == 1)

        let embeddedFailureClient = MiniMaxSequencedHTTPClient(steps: [
            .response(Data(#"{"base_resp":{"status_code":1234,"status_msg":"temporary failure"}}"#.utf8), 200),
        ])
        await #expect(throws: ProviderError.invalidResponse) {
            try await contractProvider(
                provider: "minimax",
                httpClient: embeddedFailureClient,
                preferredRegion: .china
            ).detect(apiKey: "redacted-plan-key")
        }
        #expect(await embeddedFailureClient.requestedURLs.count == 1)
    }

    @Test("Refresh uses only the persisted region")
    func refreshUsesOnlyPersistedRegion() async throws {
        let client = MiniMaxSequencedHTTPClient(steps: [.response(Data(), 401)])
        let provider = try contractProvider(
            provider: "minimax",
            httpClient: client,
            preferredRegion: .china
        )

        await #expect(throws: ProviderError.invalidCredential) {
            try await provider.fetch(
                apiKey: "redacted-plan-key",
                profile: ProviderProfile(
                    region: .international,
                    credentialKind: .tokenPlan
                )
            )
        }
        #expect(await client.requestedURLs == [
            "https://www.minimax.io/v1/token_plan/remains",
        ])
    }

    @Test("Successful payloads without recognizable quota windows are rejected")
    func payloadWithoutQuotaWindowsIsRejected() async throws {
        let payloads = [
            #"{"model_remains":[],"base_resp":{"status_code":0}}"#,
            #"{"model_remains":[{"model_name":"general"}],"base_resp":{"status_code":0}}"#,
            #"{"base_resp":{"status_code":0}}"#,
        ]

        for payload in payloads {
            let client = MiniMaxSequencedHTTPClient(steps: [
                .response(Data(payload.utf8), 200),
            ])
            await #expect(throws: ProviderError.invalidResponse) {
                try await contractProvider(
                    provider: "minimax",
                    httpClient: client,
                    preferredRegion: .china
                ).detect(apiKey: "redacted-plan-key")
            }
        }
    }

    @Test("Requests use bearer authentication and JSON headers")
    func requestsUseExpectedHeaders() async throws {
        let client = MiniMaxSequencedHTTPClient(steps: [
            .response(miniMaxQuotaPayload(), 200),
        ])
        let provider = try contractProvider(
            provider: "minimax",
            httpClient: client,
            preferredRegion: .china
        )

        _ = try await provider.detect(apiKey: "secret")
        let request = try #require(await client.requests.first)

        #expect(request.httpMethod == "GET")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer secret")
        #expect(request.value(forHTTPHeaderField: "Accept") == "application/json")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
    }

    @Test("Stored profiles reject unsupported regions and credential kinds")
    func storedProfilesRejectUnsupportedVariants() async throws {
        let client = MiniMaxSequencedHTTPClient(steps: [])
        let provider = try contractProvider(
            provider: "minimax",
            httpClient: client,
            preferredRegion: .china
        )

        await #expect(throws: ProviderError.profileMismatch) {
            try await provider.fetch(
                apiKey: "redacted-plan-key",
                profile: ProviderProfile(region: .global, credentialKind: .tokenPlan)
            )
        }
        await #expect(throws: ProviderError.profileMismatch) {
            try await provider.fetch(
                apiKey: "redacted-plan-key",
                profile: ProviderProfile(region: .china, credentialKind: .standard)
            )
        }
        #expect(await client.requestedURLs.isEmpty)
    }
}

private func miniMaxQuotaPayload() -> Data {
    Data(
        #"{"model_remains":[{"model_name":"general","remains":90,"total":100}],"base_resp":{"status_code":0}}"#.utf8
    )
}

private actor MiniMaxSequencedHTTPClient: HTTPClient {
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
