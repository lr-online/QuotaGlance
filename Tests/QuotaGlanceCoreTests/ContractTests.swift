import Foundation
import Testing
@testable import QuotaGlanceCore

// Expected-fixture decode structs. An expected file pins a subset of
// ProviderUsageSnapshot fields; only present fields are asserted.
// Multi-step cases use <case>-response2.json etc., served in the provider's
// documented request order. See Contracts/README.md for the schema.
private struct ExpectedMoney: Decodable {
    let amount: String
    let currency: String

    var money: Money {
        Money(amount: Decimal(string: amount)!, currency: currency)
    }
}

private struct ExpectedMonetaryValue: Decodable {
    let label: String
    let value: ExpectedMoney
}

private struct ExpectedBalance: Decodable {
    let label: String
    let available: ExpectedMoney
    let breakdown: [ExpectedMonetaryValue]
}

private struct ExpectedSpendingLimit: Decodable {
    let label: String
    let used: ExpectedMoney?
    let limit: ExpectedMoney?
    let remaining: ExpectedMoney?
    let resetDescription: String?
}

private struct ExpectedSpendSummary: Decodable {
    let today: ExpectedMoney?
    let week: ExpectedMoney?
    let month: ExpectedMoney?
    let total: ExpectedMoney?
}

private struct ExpectedUsageCounters: Decodable {
    let actualCost: ExpectedMoney?
    let requests: Int64?
    let inputTokens: Int64?
    let outputTokens: Int64?
    let cacheReadTokens: Int64?
    let cacheCreationTokens: Int64?
    let totalTokens: Int64?
}

private struct ExpectedDailyUsage: Decodable {
    let date: String
    let actualCost: ExpectedMoney?
    let requests: Int64?
    let totalTokens: Int64?
}

private struct ExpectedModelUsage: Decodable {
    let model: String
    let actualCost: ExpectedMoney?
    let requests: Int64?
    let totalTokens: Int64?
}

private struct ExpectedQuotaWindow: Decodable {
    let label: String
    let used: Decimal?
    let limit: Decimal?
    let remaining: Decimal?
    let unit: String
    let resetsAtMs: Int64?
}

private struct ExpectedSnapshot: Decodable {
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
// fallback) can be driven end to end.
private struct ContractURLStubHTTPClient: HTTPClient {
    let responses: [String: (body: Data, statusCode: Int)]

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
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

private func contractsDirectory(provider: String) -> URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent() // QuotaGlanceCoreTests
        .deletingLastPathComponent() // Tests
        .deletingLastPathComponent() // repository root
        .appendingPathComponent("Contracts/Providers/\(provider)", isDirectory: true)
}

private func loadFixture(provider: String, file: String) throws -> Data {
    try Data(contentsOf: contractsDirectory(provider: provider).appendingPathComponent(file))
}

private func loadExpected(provider: String, name: String) throws -> ExpectedSnapshot {
    try JSONDecoder().decode(
        ExpectedSnapshot.self,
        from: loadFixture(provider: provider, file: "\(name)-expected.json")
    )
}

private func expectMoney(_ actual: Money?, _ expected: ExpectedMoney?) {
    guard let expected else { return }
    #expect(actual == expected.money)
}

private func expectBalances(
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

private func expectCounters(
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

private func expectQuotaWindows(
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
private func expectSnapshot(
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
        let provider = DeepSeekProvider(
            httpClient: ContractURLStubHTTPClient(responses: [
                DeepSeekProvider.endpoint.absoluteString:
                    (try loadFixture(provider: "deepseek", file: "balance-response.json"), 200)
            ]),
            now: { Date(timeIntervalSince1970: 123) }
        )

        let snapshot = try await provider.fetch(apiKey: "redacted-test-key")

        expectSnapshot(snapshot, try loadExpected(provider: "deepseek", name: "balance"))
    }
}

@Suite("API Info contract fixtures")
struct APIInfoContractTests {
    @Test("API Info provider output matches the shared contract fixture")
    func providerOutputMatchesContractFixture() async throws {
        let provider = APIInfoProvider(
            httpClient: ContractURLStubHTTPClient(responses: [
                APIInfoProvider.endpoint.absoluteString:
                    (try loadFixture(provider: "apiinfo", file: "usage-response.json"), 200)
            ]),
            now: { Date(timeIntervalSince1970: 123) }
        )

        let snapshot = try await provider.fetch(apiKey: "redacted-test-key")

        expectSnapshot(snapshot, try loadExpected(provider: "apiinfo", name: "usage"))
    }
}

@Suite("Kimi contract fixtures")
struct KimiContractTests {
    @Test("Kimi provider output matches the shared contract fixture")
    func providerOutputMatchesContractFixture() async throws {
        let provider = KimiProvider(
            httpClient: ContractURLStubHTTPClient(responses: [
                KimiProvider.chinaEndpoint.absoluteString:
                    (try loadFixture(provider: "kimi", file: "china-response.json"), 200)
            ]),
            preferredRegion: .china,
            now: { Date(timeIntervalSince1970: 123) }
        )

        let snapshot = try await provider.fetch(apiKey: "redacted-test-key")

        expectSnapshot(snapshot, try loadExpected(provider: "kimi", name: "china"))
    }
}

@Suite("OpenRouter contract fixtures")
struct OpenRouterContractTests {
    @Test("OpenRouter standard key output matches the shared contract fixture")
    func standardKeyOutputMatchesContractFixture() async throws {
        let provider = OpenRouterProvider(
            httpClient: ContractURLStubHTTPClient(responses: [
                OpenRouterProvider.keyEndpoint.absoluteString:
                    (try loadFixture(provider: "openrouter", file: "key-standard-response.json"), 200)
            ]),
            now: { Date(timeIntervalSince1970: 123) }
        )

        let snapshot = try await provider.fetch(apiKey: "redacted-test-key")

        expectSnapshot(snapshot, try loadExpected(provider: "openrouter", name: "key-standard"))
    }

    @Test("OpenRouter Management Key output matches the shared contract fixture")
    func managementKeyOutputMatchesContractFixture() async throws {
        let provider = OpenRouterProvider(
            httpClient: ContractURLStubHTTPClient(responses: [
                OpenRouterProvider.keyEndpoint.absoluteString:
                    (try loadFixture(provider: "openrouter", file: "key-management-response.json"), 200),
                OpenRouterProvider.creditsEndpoint.absoluteString:
                    (try loadFixture(provider: "openrouter", file: "key-management-response2.json"), 200)
            ]),
            now: { Date(timeIntervalSince1970: 123) }
        )

        let snapshot = try await provider.fetch(apiKey: "redacted-test-key")

        expectSnapshot(snapshot, try loadExpected(provider: "openrouter", name: "key-management"))
    }
}

@Suite("MiniMax contract fixtures")
struct MiniMaxContractTests {
    @Test("MiniMax provider output matches the shared contract fixture")
    func providerOutputMatchesContractFixture() async throws {
        let provider = MiniMaxProvider(
            httpClient: ContractURLStubHTTPClient(responses: [
                MiniMaxProvider.chinaEndpoint.absoluteString:
                    (try loadFixture(provider: "minimax", file: "remains-response.json"), 200)
            ]),
            preferredRegion: .china,
            now: { Date(timeIntervalSince1970: 123) }
        )

        let snapshot = try await provider.fetch(apiKey: "redacted-test-key")

        expectSnapshot(snapshot, try loadExpected(provider: "minimax", name: "remains"))
    }
}

@Suite("BioMap Coding contract fixtures")
struct BioMapCodingContractTests {
    @Test("BioMap Coding key info output matches the shared contract fixture")
    func budgetOutputMatchesContractFixture() async throws {
        let provider = BioMapCodingProvider(
            httpClient: ContractURLStubHTTPClient(responses: [
                BioMapCodingProvider.keyInfoEndpoint.absoluteString:
                    (try loadFixture(provider: "biomapcoding", file: "budget-response.json"), 200)
            ]),
            now: { Date(timeIntervalSince1970: 123) }
        )

        let snapshot = try await provider.fetch(apiKey: "redacted-test-key")

        expectSnapshot(snapshot, try loadExpected(provider: "biomapcoding", name: "budget"))
    }

    @Test("BioMap Coding models fallback output matches the shared contract fixture")
    func modelsFallbackOutputMatchesContractFixture() async throws {
        let provider = BioMapCodingProvider(
            httpClient: ContractURLStubHTTPClient(responses: [
                BioMapCodingProvider.keyInfoEndpoint.absoluteString:
                    (try loadFixture(provider: "biomapcoding", file: "fallback-response.json"), 403),
                BioMapCodingProvider.modelsEndpoint.absoluteString:
                    (try loadFixture(provider: "biomapcoding", file: "fallback-response2.json"), 200)
            ]),
            now: { Date(timeIntervalSince1970: 123) }
        )

        let snapshot = try await provider.fetch(apiKey: "redacted-test-key")

        expectSnapshot(snapshot, try loadExpected(provider: "biomapcoding", name: "fallback"))
    }
}
