import Foundation
import Testing
@testable import QuotaGlanceCore

@Suite("Alibaba Cloud Model Studio provider")
struct BailianProviderTests {
    @Test("Official public and workspace endpoints are normalized")
    func officialEndpointsAreNormalized() throws {
        let values = [
            (
                "https://dashscope.aliyuncs.com",
                "https://dashscope.aliyuncs.com/compatible-mode/v1",
                ProviderRegion.china
            ),
            (
                "https://llm-test.cn-beijing.maas.aliyuncs.com/compatible-mode/v1/",
                "https://llm-test.cn-beijing.maas.aliyuncs.com/compatible-mode/v1",
                ProviderRegion.china
            ),
            (
                "https://dashscope-intl.aliyuncs.com/compatible-mode/v1",
                "https://dashscope-intl.aliyuncs.com/compatible-mode/v1",
                ProviderRegion.international
            ),
            (
                "https://workspace.ap-northeast-1.maas.aliyuncs.com",
                "https://workspace.ap-northeast-1.maas.aliyuncs.com/compatible-mode/v1",
                ProviderRegion.international
            ),
        ]

        for (input, expected, region) in values {
            let normalized = try BailianEndpoint.normalizedBaseURL(from: input)
            #expect(normalized.absoluteString == expected)
            #expect(try BailianEndpoint.region(for: normalized) == region)
        }
    }

    @Test("Detection calls the OpenAI-compatible model list")
    func detectionCallsModelList() async throws {
        let client = BailianRecordingHTTPClient(
            data: modelList("qwen-plus", "qwen-max"),
            statusCode: 200
        )
        let provider = BailianProvider(
            httpClient: client,
            now: { Date(timeIntervalSince1970: 123) }
        )
        let configuration = ProviderConfiguration(
            baseURL: URL(
                string: "https://llm-test.cn-beijing.maas.aliyuncs.com/compatible-mode/v1"
            )!
        )

        let detection = try await provider.detect(
            apiKey: "secret",
            configuration: configuration
        )
        let request = await client.lastRequest

        #expect(provider.id == .bailian)
        #expect(
            detection.profile
                == ProviderProfile(region: .china, credentialKind: .standard)
        )
        #expect(detection.snapshot.providerStatus == "connected")
        #expect(
            detection.snapshot.metricsUnavailableReason
                == "2 models available. Billing metrics unavailable for this API key."
        )
        #expect(detection.snapshot.receivedAt == Date(timeIntervalSince1970: 123))
        #expect(detection.snapshot.balances.isEmpty)
        #expect(detection.snapshot.spendingLimit == nil)
        #expect(detection.snapshot.quotaWindows.isEmpty)
        #expect(
            request?.url?.absoluteString
                == "https://llm-test.cn-beijing.maas.aliyuncs.com/compatible-mode/v1/models"
        )
        #expect(request?.httpMethod == "GET")
        #expect(request?.value(forHTTPHeaderField: "Authorization") == "Bearer secret")
        #expect(request?.value(forHTTPHeaderField: "Accept") == "application/json")
    }

    @Test("Missing configuration uses the public Beijing endpoint")
    func missingConfigurationUsesPublicEndpoint() async throws {
        let client = BailianRecordingHTTPClient(
            data: modelList("qwen-plus"),
            statusCode: 200
        )
        let provider = BailianProvider(httpClient: client)

        let detection = try await provider.detect(apiKey: "secret")
        let request = await client.lastRequest

        #expect(detection.profile.region == .china)
        #expect(
            request?.url?.absoluteString
                == "https://dashscope.aliyuncs.com/compatible-mode/v1/models"
        )
    }

    @Test("International endpoints persist an international profile")
    func internationalEndpointIsDetected() async throws {
        let provider = BailianProvider(
            httpClient: BailianStubHTTPClient(
                data: modelList("qwen-plus"),
                statusCode: 200
            )
        )
        let configuration = ProviderConfiguration(
            baseURL: URL(
                string: "https://workspace.ap-southeast-1.maas.aliyuncs.com/compatible-mode/v1"
            )!
        )

        let detection = try await provider.detect(
            apiKey: "redacted-test-key",
            configuration: configuration
        )

        #expect(detection.profile.region == .international)
    }

    @Test("HTTP authentication and rate-limit failures stay typed", arguments: [
        (401, ProviderError.invalidCredential),
        (403, ProviderError.invalidCredential),
        (429, ProviderError.rateLimited),
        (503, ProviderError.httpStatus(503)),
    ])
    func httpFailuresStayTyped(statusCode: Int, expected: ProviderError) async {
        let provider = BailianProvider(
            httpClient: BailianStubHTTPClient(data: Data(), statusCode: statusCode)
        )

        await #expect(throws: expected) {
            try await provider.detect(apiKey: "redacted-test-key")
        }
    }

    @Test("Malformed or empty model lists are rejected", arguments: [
        #"{}"#,
        #"{"object":"error","data":[]}"#,
        #"{"object":"list","data":[]}"#,
        #"{"object":"list","data":[{"id":""}]}"#,
    ])
    func malformedModelListsAreRejected(payload: String) async {
        let provider = BailianProvider(
            httpClient: BailianStubHTTPClient(
                data: Data(payload.utf8),
                statusCode: 200
            )
        )

        await #expect(throws: ProviderError.invalidResponse) {
            try await provider.detect(apiKey: "redacted-test-key")
        }
    }

    @Test("Refresh rejects a profile from another endpoint region")
    func refreshRejectsProfileMismatch() async {
        let provider = BailianProvider(
            httpClient: BailianStubHTTPClient(
                data: modelList("qwen-plus"),
                statusCode: 200
            )
        )
        let configuration = ProviderConfiguration(
            baseURL: BailianEndpoint.defaultBaseURL
        )

        await #expect(throws: ProviderError.profileMismatch) {
            try await provider.fetch(
                apiKey: "redacted-test-key",
                profile: ProviderProfile(
                    region: .international,
                    credentialKind: .standard
                ),
                configuration: configuration
            )
        }
    }
}

private func modelList(_ identifiers: String...) -> Data {
    let data = identifiers.map { ["id": $0, "object": "model"] }
    return try! JSONSerialization.data(
        withJSONObject: ["object": "list", "data": data]
    )
}

private struct BailianStubHTTPClient: HTTPClient {
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

private actor BailianRecordingHTTPClient: HTTPClient {
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
