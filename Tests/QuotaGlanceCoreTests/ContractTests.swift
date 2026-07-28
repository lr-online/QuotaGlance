import Foundation
import Testing
@testable import QuotaGlanceCore

@Suite("DeepSeek contract fixtures")
struct DeepSeekContractTests {
    private struct ExpectedMoney: Decodable {
        let amount: String
        let currency: String
    }

    private struct ExpectedBreakdownItem: Decodable {
        let label: String
        let value: ExpectedMoney
    }

    private struct ExpectedBalance: Decodable {
        let label: String
        let available: ExpectedMoney
        let breakdown: [ExpectedBreakdownItem]
    }

    private struct ExpectedSnapshot: Decodable {
        let balances: [ExpectedBalance]
        let providerStatus: String
    }

    private struct ContractStubHTTPClient: HTTPClient {
        let data: Data

        func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: nil
            )!
            return (data, response)
        }
    }

    private static func contractsDirectory() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // QuotaGlanceCoreTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // repository root
            .appendingPathComponent("Contracts/Providers/deepseek", isDirectory: true)
    }

    @Test("DeepSeek provider output matches the shared contract fixture")
    func providerOutputMatchesContractFixture() async throws {
        let directory = Self.contractsDirectory()
        let responseData = try Data(
            contentsOf: directory.appendingPathComponent("balance-response.json")
        )
        let expectedData = try Data(
            contentsOf: directory.appendingPathComponent("balance-expected.json")
        )
        let expected = try JSONDecoder().decode(ExpectedSnapshot.self, from: expectedData)

        let provider = DeepSeekProvider(
            httpClient: ContractStubHTTPClient(data: responseData),
            now: { Date(timeIntervalSince1970: 123) }
        )
        let snapshot = try await provider.fetch(apiKey: "redacted-test-key")

        #expect(snapshot.providerStatus == expected.providerStatus)
        #expect(snapshot.balances.count == expected.balances.count)
        for (actual, expectedBalance) in zip(snapshot.balances, expected.balances) {
            #expect(actual.label == expectedBalance.label)
            #expect(
                actual.available == Money(
                    amount: Decimal(string: expectedBalance.available.amount)!,
                    currency: expectedBalance.available.currency
                )
            )
            #expect(actual.breakdown.count == expectedBalance.breakdown.count)
            for (actualItem, expectedItem) in zip(actual.breakdown, expectedBalance.breakdown) {
                #expect(actualItem.label == expectedItem.label)
                #expect(
                    actualItem.value == Money(
                        amount: Decimal(string: expectedItem.value.amount)!,
                        currency: expectedItem.value.currency
                    )
                )
            }
        }
    }
}
