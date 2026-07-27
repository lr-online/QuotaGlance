import Foundation
import Testing
@testable import QuotaGlanceCore

@Suite("DeepSeek provider")
struct DeepSeekProviderTests {
    @Test("Detection maps every currency and balance breakdown")
    func detectionMapsEveryCurrencyAndBreakdown() async throws {
        let data = Data(
            #"{"is_available":true,"balance_infos":[{"currency":"CNY","total_balance":"12.34","granted_balance":"2.34","topped_up_balance":"10.00"},{"currency":"USD","total_balance":"5.67","granted_balance":"0.67","topped_up_balance":"5.00"}]}"#.utf8
        )
        let provider = DeepSeekProvider(
            httpClient: DeepSeekStubHTTPClient(data: data, statusCode: 200),
            now: { Date(timeIntervalSince1970: 123) }
        )

        let detection = try await provider.detect(apiKey: "redacted-test-key")

        #expect(provider.id == .deepSeek)
        #expect(
            detection.profile
                == ProviderProfile(region: .global, credentialKind: .standard)
        )
        #expect(detection.snapshot.providerStatus == "active")
        #expect(detection.snapshot.receivedAt == Date(timeIntervalSince1970: 123))
        #expect(
            detection.snapshot.balances.map(\.available) == [
                Money(amount: Decimal(string: "12.34")!, currency: "CNY"),
                Money(amount: Decimal(string: "5.67")!, currency: "USD"),
            ]
        )
        #expect(
            detection.snapshot.balances[0].breakdown == [
                MonetaryValue(
                    label: "Granted",
                    value: Money(amount: Decimal(string: "2.34")!, currency: "CNY")
                ),
                MonetaryValue(
                    label: "Topped up",
                    value: Money(amount: Decimal(string: "10.00")!, currency: "CNY")
                ),
            ]
        )
    }

    @Test("Request uses the official endpoint and bearer authentication")
    func requestUsesOfficialEndpointAndBearerAuthentication() async throws {
        let client = DeepSeekRecordingHTTPClient(
            data: Data(
                #"{"is_available":true,"balance_infos":[{"currency":"CNY","total_balance":"1","granted_balance":"0","topped_up_balance":"1"}]}"#.utf8
            ),
            statusCode: 200
        )
        let provider = DeepSeekProvider(httpClient: client)

        _ = try await provider.fetch(
            apiKey: "secret",
            profile: ProviderProfile(region: .global, credentialKind: .standard)
        )
        let request = await client.lastRequest

        #expect(request?.url?.absoluteString == "https://api.deepseek.com/user/balance")
        #expect(request?.httpMethod == "GET")
        #expect(request?.value(forHTTPHeaderField: "Authorization") == "Bearer secret")
        #expect(request?.value(forHTTPHeaderField: "Accept") == "application/json")
    }

    @Test("An unavailable balance response remains a valid snapshot")
    func unavailableBalanceRemainsValid() async throws {
        let data = Data(
            #"{"is_available":false,"balance_infos":[{"currency":"CNY","total_balance":"0","granted_balance":"0","topped_up_balance":"0"}]}"#.utf8
        )
        let provider = DeepSeekProvider(
            httpClient: DeepSeekStubHTTPClient(data: data, statusCode: 200)
        )

        let snapshot = try await provider.fetch(
            apiKey: "redacted-test-key",
            profile: ProviderProfile(region: .global, credentialKind: .standard)
        )

        #expect(snapshot.providerStatus == "unavailable")
        #expect(snapshot.primaryBalance?.available == Money(amount: 0, currency: "CNY"))
    }

    @Test("HTTP authentication and rate-limit failures stay typed", arguments: [
        (401, ProviderError.invalidCredential),
        (403, ProviderError.invalidCredential),
        (429, ProviderError.rateLimited),
        (503, ProviderError.httpStatus(503)),
    ])
    func httpFailuresStayTyped(statusCode: Int, expected: ProviderError) async {
        let provider = DeepSeekProvider(
            httpClient: DeepSeekStubHTTPClient(data: Data(), statusCode: statusCode)
        )

        await #expect(throws: expected) {
            try await provider.detect(apiKey: "redacted-test-key")
        }
    }

    @Test("Malformed or empty balance payloads are rejected", arguments: [
        #"{"is_available":true}"#,
        #"{"is_available":true,"balance_infos":[]}"#,
        #"{"is_available":true,"balance_infos":[{"currency":"","total_balance":"1"}]}"#,
        #"{"is_available":true,"balance_infos":[{"currency":"CNY","total_balance":"not-a-number"}]}"#,
    ])
    func malformedOrEmptyPayloadsAreRejected(payload: String) async {
        let provider = DeepSeekProvider(
            httpClient: DeepSeekStubHTTPClient(
                data: Data(payload.utf8),
                statusCode: 200
            )
        )

        await #expect(throws: ProviderError.invalidResponse) {
            try await provider.detect(apiKey: "redacted-test-key")
        }
    }

    @Test("Stored profiles must match DeepSeek's global standard credential")
    func storedProfilesMustMatch() async {
        let provider = DeepSeekProvider(
            httpClient: DeepSeekStubHTTPClient(data: Data(), statusCode: 200)
        )

        await #expect(throws: ProviderError.profileMismatch) {
            try await provider.fetch(
                apiKey: "redacted-test-key",
                profile: ProviderProfile(region: .china, credentialKind: .standard)
            )
        }
    }
}

private struct DeepSeekStubHTTPClient: HTTPClient {
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

private actor DeepSeekRecordingHTTPClient: HTTPClient {
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
