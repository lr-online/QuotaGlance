import Foundation
import Testing
@testable import QuotaGlanceCore

@Suite("Provider registry")
struct ProviderRegistryTests {
    @Test("Registry resolves providers by stable identity")
    func registryResolvesProviderIdentity() throws {
        let registry = ProviderRegistry(providers: [RegistryStubProvider(id: .deepSeek)])

        let provider = try registry.provider(for: .deepSeek)

        #expect(provider.id == .deepSeek)
    }

    @Test("Registry reports an unavailable provider")
    func registryReportsUnavailableProvider() {
        let registry = ProviderRegistry(providers: [])

        #expect(throws: ProviderError.providerUnavailable(.kimi)) {
            try registry.provider(for: .kimi)
        }
    }
}

private struct RegistryStubProvider: UsageProvider {
    let id: ProviderID

    var descriptor: ProviderDescriptor {
        ProviderCatalog.descriptor(for: id)
    }

    func detect(apiKey: String) async throws -> ProviderDetection {
        ProviderDetection(
            profile: .apiInfo,
            snapshot: ProviderUsageSnapshot(receivedAt: .now)
        )
    }

    func fetch(
        apiKey: String,
        profile: ProviderProfile
    ) async throws -> ProviderUsageSnapshot {
        ProviderUsageSnapshot(receivedAt: .now)
    }
}
