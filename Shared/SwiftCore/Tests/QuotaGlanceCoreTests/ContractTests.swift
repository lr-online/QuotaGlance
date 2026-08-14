import Foundation
import Testing
@testable import QuotaGlanceCore

// Expected-fixture decode structs. An expected file pins a subset of
// ProviderUsageSnapshot fields; only present fields are asserted.
// Multi-step cases use <case>-response2.json etc., served in the provider's
// documented request order. See Contracts/README.md for the schema.
// The helpers in this file are internal (not private) so the engine semantics
// suite (SpecEngineTests.swift) and the per-provider suites can share them.
struct ExpectedMoney: Decodable {
    let amount: String
    let currency: String

    var money: Money {
        Money(amount: Decimal(string: amount)!, currency: currency)
    }
}

struct ExpectedMonetaryValue: Decodable {
    let label: String
    let value: ExpectedMoney
}

struct ExpectedBalance: Decodable {
    let label: String
    let available: ExpectedMoney
    let breakdown: [ExpectedMonetaryValue]
}

struct ExpectedSpendingLimit: Decodable {
    let label: String
    let used: ExpectedMoney?
    let limit: ExpectedMoney?
    let remaining: ExpectedMoney?
    let resetDescription: String?
}

struct ExpectedSpendSummary: Decodable {
    let today: ExpectedMoney?
    let week: ExpectedMoney?
    let month: ExpectedMoney?
    let total: ExpectedMoney?
}

struct ExpectedUsageCounters: Decodable {
    let actualCost: ExpectedMoney?
    let requests: Int64?
    let inputTokens: Int64?
    let outputTokens: Int64?
    let cacheReadTokens: Int64?
    let cacheCreationTokens: Int64?
    let totalTokens: Int64?
}

struct ExpectedDailyUsage: Decodable {
    let date: String
    let actualCost: ExpectedMoney?
    let requests: Int64?
    let totalTokens: Int64?
}

struct ExpectedModelUsage: Decodable {
    let model: String
    let actualCost: ExpectedMoney?
    let requests: Int64?
    let totalTokens: Int64?
}

struct ExpectedQuotaWindow: Decodable {
    let label: String
    let used: Decimal?
    let limit: Decimal?
    let remaining: Decimal?
    let unit: String
    let resetsAtMs: Int64?
}

struct ExpectedSnapshot: Decodable {
    let balances: [ExpectedBalance]?
    let spendingLimit: ExpectedSpendingLimit?
    let spend: ExpectedSpendSummary?
    let quotaWindows: [ExpectedQuotaWindow]?
    let today: ExpectedUsageCounters?
    let total: ExpectedUsageCounters?
    let dailyUsage: [ExpectedDailyUsage]?
    let modelUsage: [ExpectedModelUsage]?
    let providerStatus: String?
    let metricsUnavailableReason: String?
}

// URL-keyed stub: serves the fixture body and status registered for each
// request URL, so multi-step providers (OpenRouter credits, BioMap Coding
// fallback) can be driven end to end. Every request is recorded in order so
// <case>-requests.json fixtures can pin the request sequence; the actor keeps
// the recording async-safe even though the tests run single-concurrency.
actor ContractRequestRecorder {
    private(set) var requests: [URLRequest] = []

    func record(_ request: URLRequest) {
        requests.append(request)
    }
}

final class ContractURLStubHTTPClient: HTTPClient {
    let responses: [String: (body: Data, statusCode: Int)]
    let recorder = ContractRequestRecorder()

    init(responses: [String: (body: Data, statusCode: Int)]) {
        self.responses = responses
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        await recorder.record(request)

        guard let stub = responses[request.url!.absoluteString] else {
            throw ProviderError.invalidResponse
        }
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: stub.statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: nil
        )!
        return (stub.body, response)
    }
}

func contractsDirectory(provider: String) -> URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent() // QuotaGlanceCoreTests
        .deletingLastPathComponent() // Tests
        .deletingLastPathComponent() // Shared/SwiftCore
        .deletingLastPathComponent() // Shared
        .deletingLastPathComponent() // repository root
        .appendingPathComponent("Contracts/Providers/\(provider)", isDirectory: true)
}

func loadFixture(provider: String, file: String) throws -> Data {
    try Data(contentsOf: contractsDirectory(provider: provider).appendingPathComponent(file))
}

func loadExpected(provider: String, name: String) throws -> ExpectedSnapshot {
    try JSONDecoder().decode(
        ExpectedSnapshot.self,
        from: loadFixture(provider: provider, file: "\(name)-expected.json")
    )
}

// Requests-fixture decode struct. A requests file pins the exact request
// sequence a fetch issues; header values are assertion patterns, not literal
// values. See Contracts/README.md for the schema.
struct ExpectedRequest: Decodable {
    let method: String
    let url: String
    let headers: [String: String]
}

// Returns nil when the case has no <case>-requests.json fixture yet.
func loadExpectedRequests(provider: String, name: String) throws -> [ExpectedRequest]? {
    let fileURL = contractsDirectory(provider: provider)
        .appendingPathComponent("\(name)-requests.json")
    guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
    return try JSONDecoder().decode([ExpectedRequest].self, from: Data(contentsOf: fileURL))
}

// Builds a SpecDrivenProvider executing Contracts/Providers/<id>/spec.json
// against the stub client; the fixed clock matches what the fixtures pin.
func contractProvider(
    provider: String,
    httpClient: any HTTPClient,
    preferredRegion: ProviderRegion? = nil,
    now: @escaping @Sendable () -> Date = { Date(timeIntervalSince1970: 123) }
) throws -> SpecDrivenProvider {
    try SpecDrivenProvider(
        specData: loadFixture(provider: provider, file: "spec.json"),
        httpClient: httpClient,
        preferredRegion: preferredRegion,
        now: now
    )
}

// Asserts the recorded request sequence against a requests fixture: count,
// order, method and URL match exactly; header values are assertion patterns —
// "Bearer" requires the header to be present with the Bearer scheme (the API
// key itself is never pinned), any other string is an exact-value match.
func expectRequests(_ actual: [URLRequest], _ expected: [ExpectedRequest]) {
    #expect(actual.count == expected.count)
    for (request, expectedRequest) in zip(actual, expected) {
        #expect(request.httpMethod == expectedRequest.method)
        #expect(request.url?.absoluteString == expectedRequest.url)
        for (field, pattern) in expectedRequest.headers {
            let value = request.value(forHTTPHeaderField: field)
            if pattern == "Bearer" {
                #expect(value?.hasPrefix("Bearer ") == true)
            } else {
                #expect(value == pattern)
            }
        }
    }
}

func expectMoney(_ actual: Money?, _ expected: ExpectedMoney?) {
    guard let expected else { return }
    #expect(actual == expected.money)
}

func expectBalances(
    _ actual: [MonetaryBalance],
    _ expected: [ExpectedBalance]
) {
    #expect(actual.count == expected.count)
    for (actualBalance, expectedBalance) in zip(actual, expected) {
        #expect(actualBalance.label == expectedBalance.label)
        #expect(actualBalance.available == expectedBalance.available.money)
        #expect(actualBalance.breakdown.count == expectedBalance.breakdown.count)
        for (actualItem, expectedItem) in zip(actualBalance.breakdown, expectedBalance.breakdown) {
            #expect(actualItem.label == expectedItem.label)
            #expect(actualItem.value == expectedItem.value.money)
        }
    }
}

func expectCounters(
    _ actual: UsageCounters?,
    _ expected: ExpectedUsageCounters?
) {
    guard let expected else { return }
    guard let counters = actual else {
        #expect(actual != nil)
        return
    }
    expectMoney(counters.actualCost, expected.actualCost)
    if let requests = expected.requests {
        #expect(counters.requests == requests)
    }
    if let inputTokens = expected.inputTokens {
        #expect(counters.inputTokens == inputTokens)
    }
    if let outputTokens = expected.outputTokens {
        #expect(counters.outputTokens == outputTokens)
    }
    if let cacheReadTokens = expected.cacheReadTokens {
        #expect(counters.cacheReadTokens == cacheReadTokens)
    }
    if let cacheCreationTokens = expected.cacheCreationTokens {
        #expect(counters.cacheCreationTokens == cacheCreationTokens)
    }
    if let totalTokens = expected.totalTokens {
        #expect(counters.totalTokens == totalTokens)
    }
}

func expectQuotaWindows(
    _ actual: [QuotaWindow],
    _ expected: [ExpectedQuotaWindow]
) {
    #expect(actual.count == expected.count)
    for (window, expectedWindow) in zip(actual, expected) {
        #expect(window.label == expectedWindow.label)
        #expect(window.unit == expectedWindow.unit)
        if let used = expectedWindow.used {
            #expect(window.used == used)
        }
        if let limit = expectedWindow.limit {
            #expect(window.limit == limit)
        }
        if let remaining = expectedWindow.remaining {
            #expect(window.remaining == remaining)
        }
        if let resetsAtMs = expectedWindow.resetsAtMs {
            #expect(
                window.resetsAt == Date(timeIntervalSince1970: TimeInterval(resetsAtMs) / 1000)
            )
        }
    }
}

// Asserts every section pinned by an expected fixture against a snapshot.
func expectSnapshot(
    _ snapshot: ProviderUsageSnapshot,
    _ expected: ExpectedSnapshot
) {
    if let expectedBalances = expected.balances {
        expectBalances(snapshot.balances, expectedBalances)
    }
    if let expectedLimit = expected.spendingLimit {
        guard let limit = snapshot.spendingLimit else {
            #expect(snapshot.spendingLimit != nil)
            return
        }
        #expect(limit.label == expectedLimit.label)
        expectMoney(limit.used, expectedLimit.used)
        expectMoney(limit.limit, expectedLimit.limit)
        expectMoney(limit.remaining, expectedLimit.remaining)
        if let resetDescription = expectedLimit.resetDescription {
            #expect(limit.resetDescription == resetDescription)
        }
    }
    if let expectedSpend = expected.spend {
        expectMoney(snapshot.spend.today, expectedSpend.today)
        expectMoney(snapshot.spend.week, expectedSpend.week)
        expectMoney(snapshot.spend.month, expectedSpend.month)
        expectMoney(snapshot.spend.total, expectedSpend.total)
    }
    if let expectedWindows = expected.quotaWindows {
        expectQuotaWindows(snapshot.quotaWindows, expectedWindows)
    }
    expectCounters(snapshot.today, expected.today)
    expectCounters(snapshot.total, expected.total)
    if let expectedDaily = expected.dailyUsage {
        #expect(snapshot.dailyUsage.count == expectedDaily.count)
        for (actualEntry, expectedEntry) in zip(snapshot.dailyUsage, expectedDaily) {
            #expect(actualEntry.date == expectedEntry.date)
            #expect(actualEntry.actualCost == expectedEntry.actualCost?.money)
            if let requests = expectedEntry.requests {
                #expect(actualEntry.requests == requests)
            }
            if let totalTokens = expectedEntry.totalTokens {
                #expect(actualEntry.totalTokens == totalTokens)
            }
        }
    }
    if let expectedModels = expected.modelUsage {
        #expect(snapshot.modelUsage.count == expectedModels.count)
        for (actualEntry, expectedEntry) in zip(snapshot.modelUsage, expectedModels) {
            #expect(actualEntry.model == expectedEntry.model)
            expectMoney(actualEntry.actualCost, expectedEntry.actualCost)
            if let requests = expectedEntry.requests {
                #expect(actualEntry.requests == requests)
            }
            if let totalTokens = expectedEntry.totalTokens {
                #expect(actualEntry.totalTokens == totalTokens)
            }
        }
    }
    if let expectedStatus = expected.providerStatus {
        #expect(snapshot.providerStatus == expectedStatus)
    }
    if let expectedReason = expected.metricsUnavailableReason {
        #expect(snapshot.metricsUnavailableReason == expectedReason)
    }
}

@Suite("DeepSeek contract fixtures")
struct DeepSeekContractTests {
    @Test("DeepSeek provider output matches the shared contract fixture")
    func providerOutputMatchesContractFixture() async throws {
        let httpClient = ContractURLStubHTTPClient(responses: [
            "https://api.deepseek.com/user/balance":
                (try loadFixture(provider: "deepseek", file: "balance-response.json"), 200)
        ])
        let provider = try contractProvider(provider: "deepseek", httpClient: httpClient)

        let snapshot = try await provider.fetch(
            apiKey: "redacted-test-key",
            profile: ProviderProfile(region: .global, credentialKind: .standard)
        )

        expectSnapshot(snapshot, try loadExpected(provider: "deepseek", name: "balance"))
        if let expectedRequests = try loadExpectedRequests(provider: "deepseek", name: "balance") {
            expectRequests(await httpClient.recorder.requests, expectedRequests)
        }
    }
}

@Suite("API Info contract fixtures")
struct APIInfoContractTests {
    @Test("API Info provider output matches the shared contract fixture")
    func providerOutputMatchesContractFixture() async throws {
        let httpClient = ContractURLStubHTTPClient(responses: [
            "https://www.api-info.net/v1/usage":
                (try loadFixture(provider: "apiinfo", file: "usage-response.json"), 200)
        ])
        let provider = try contractProvider(provider: "apiinfo", httpClient: httpClient)

        let snapshot = try await provider.fetch(
            apiKey: "redacted-test-key",
            profile: .apiInfo
        )

        expectSnapshot(snapshot, try loadExpected(provider: "apiinfo", name: "usage"))
        if let expectedRequests = try loadExpectedRequests(provider: "apiinfo", name: "usage") {
            expectRequests(await httpClient.recorder.requests, expectedRequests)
        }
    }
}

@Suite("Kimi contract fixtures")
struct KimiContractTests {
    @Test("Kimi provider output matches the shared contract fixture")
    func providerOutputMatchesContractFixture() async throws {
        let httpClient = ContractURLStubHTTPClient(responses: [
            "https://api.moonshot.cn/v1/users/me/balance":
                (try loadFixture(provider: "kimi", file: "china-response.json"), 200)
        ])
        let provider = try contractProvider(
            provider: "kimi",
            httpClient: httpClient,
            preferredRegion: .china
        )

        let snapshot = try await provider.fetch(
            apiKey: "redacted-test-key",
            profile: ProviderProfile(region: .china, credentialKind: .standard)
        )

        expectSnapshot(snapshot, try loadExpected(provider: "kimi", name: "china"))
        if let expectedRequests = try loadExpectedRequests(provider: "kimi", name: "china") {
            expectRequests(await httpClient.recorder.requests, expectedRequests)
        }
    }
}

@Suite("OpenRouter contract fixtures")
struct OpenRouterContractTests {
    @Test("OpenRouter standard key output matches the shared contract fixture")
    func standardKeyOutputMatchesContractFixture() async throws {
        let httpClient = ContractURLStubHTTPClient(responses: [
            "https://openrouter.ai/api/v1/key":
                (try loadFixture(provider: "openrouter", file: "key-standard-response.json"), 200)
        ])
        let provider = try contractProvider(provider: "openrouter", httpClient: httpClient)

        let snapshot = try await provider.fetch(
            apiKey: "redacted-test-key",
            profile: ProviderProfile(region: .global, credentialKind: .standard)
        )

        expectSnapshot(snapshot, try loadExpected(provider: "openrouter", name: "key-standard"))
        if let expectedRequests = try loadExpectedRequests(provider: "openrouter", name: "key-standard") {
            expectRequests(await httpClient.recorder.requests, expectedRequests)
        }
    }

    @Test("OpenRouter Management Key output matches the shared contract fixture")
    func managementKeyOutputMatchesContractFixture() async throws {
        let httpClient = ContractURLStubHTTPClient(responses: [
            "https://openrouter.ai/api/v1/key":
                (try loadFixture(provider: "openrouter", file: "key-management-response.json"), 200),
            "https://openrouter.ai/api/v1/credits":
                (try loadFixture(provider: "openrouter", file: "key-management-response2.json"), 200)
        ])
        let provider = try contractProvider(provider: "openrouter", httpClient: httpClient)

        let snapshot = try await provider.fetch(
            apiKey: "redacted-test-key",
            profile: ProviderProfile(region: .global, credentialKind: .management)
        )

        expectSnapshot(snapshot, try loadExpected(provider: "openrouter", name: "key-management"))
        if let expectedRequests = try loadExpectedRequests(provider: "openrouter", name: "key-management") {
            expectRequests(await httpClient.recorder.requests, expectedRequests)
        }
    }
}

@Suite("MiniMax contract fixtures")
struct MiniMaxContractTests {
    @Test("MiniMax provider output matches the shared contract fixture")
    func providerOutputMatchesContractFixture() async throws {
        let httpClient = ContractURLStubHTTPClient(responses: [
            "https://www.minimaxi.com/v1/token_plan/remains":
                (try loadFixture(provider: "minimax", file: "remains-response.json"), 200)
        ])
        let provider = try contractProvider(
            provider: "minimax",
            httpClient: httpClient,
            preferredRegion: .china
        )

        let snapshot = try await provider.fetch(
            apiKey: "redacted-test-key",
            profile: ProviderProfile(region: .china, credentialKind: .tokenPlan)
        )

        expectSnapshot(snapshot, try loadExpected(provider: "minimax", name: "remains"))
        if let expectedRequests = try loadExpectedRequests(provider: "minimax", name: "remains") {
            expectRequests(await httpClient.recorder.requests, expectedRequests)
        }
    }
}

@Suite("BioMap Coding contract fixtures")
struct BioMapCodingContractTests {
    @Test("BioMap Coding key info output matches the shared contract fixture")
    func budgetOutputMatchesContractFixture() async throws {
        let httpClient = ContractURLStubHTTPClient(responses: [
            "https://coding.biomap-int.com/key/info":
                (try loadFixture(provider: "biomapcoding", file: "budget-response.json"), 200)
        ])
        let provider = try contractProvider(provider: "biomapcoding", httpClient: httpClient)

        let snapshot = try await provider.fetch(
            apiKey: "redacted-test-key",
            profile: ProviderProfile(region: .global, credentialKind: .standard)
        )

        expectSnapshot(snapshot, try loadExpected(provider: "biomapcoding", name: "budget"))
        if let expectedRequests = try loadExpectedRequests(provider: "biomapcoding", name: "budget") {
            expectRequests(await httpClient.recorder.requests, expectedRequests)
        }
    }

    @Test("BioMap Coding models fallback output matches the shared contract fixture")
    func modelsFallbackOutputMatchesContractFixture() async throws {
        let httpClient = ContractURLStubHTTPClient(responses: [
            "https://coding.biomap-int.com/key/info":
                (try loadFixture(provider: "biomapcoding", file: "fallback-response.json"), 403),
            "https://coding.biomap-int.com/v1/models":
                (try loadFixture(provider: "biomapcoding", file: "fallback-response2.json"), 200)
        ])
        let provider = try contractProvider(provider: "biomapcoding", httpClient: httpClient)

        let snapshot = try await provider.fetch(
            apiKey: "redacted-test-key",
            profile: ProviderProfile(region: .global, credentialKind: .standard)
        )

        expectSnapshot(snapshot, try loadExpected(provider: "biomapcoding", name: "fallback"))
        if let expectedRequests = try loadExpectedRequests(provider: "biomapcoding", name: "fallback") {
            expectRequests(await httpClient.recorder.requests, expectedRequests)
        }
    }
}
