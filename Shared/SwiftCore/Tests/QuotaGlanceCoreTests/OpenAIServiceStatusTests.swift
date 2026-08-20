import Foundation
import Testing
@testable import QuotaGlanceCore

@Suite("OpenAI service status")
struct OpenAIServiceStatusTests {
    @Test("summary fixtures map to the stable service-health model", arguments: ["openai-summary", "openai-degraded"])
    func mapsSharedFixture(name: String) throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // QuotaGlanceCoreTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // Shared/SwiftCore
            .deletingLastPathComponent() // Shared
            .deletingLastPathComponent() // repository root
            .appendingPathComponent("Contracts/ServiceStatus")
        let actual = try OpenAIServiceStatusClient.parse(Data(contentsOf: root.appendingPathComponent("\(name)-response.json")))
        let expected = try JSONDecoder().decode(OpenAIServiceStatus.self, from: Data(contentsOf: root.appendingPathComponent("\(name)-expected.json")))
        #expect(actual == expected)
    }
}
