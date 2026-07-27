import Foundation
import Testing
@testable import QuotaGlanceCore

@Suite("User-facing error messages")
struct ErrorPresentationTests {
    @Test("Keychain interaction requirements explain how to unlock")
    func keychainInteractionRequirementIsActionable() {
        let message = ErrorPresenter.message(
            for: CredentialStoreError.interactionRequired
        )

        #expect(message.contains("Keychain"))
        #expect(message.contains("Refresh"))
    }

    @Test("Keychain code-object failures explain how to recover")
    func keychainCodeObjectFailureIsActionable() {
        let message = ErrorPresenter.message(
            for: CredentialStoreError.unexpectedStatus(-67068)
        )

        #expect(message.contains("Keychain"))
        #expect(message.contains("reopen"))
    }

    @Test("Provider HTTP failures include the response status")
    func providerHTTPFailureIncludesStatus() {
        let message = ErrorPresenter.message(for: ProviderError.httpStatus(500))

        #expect(message.contains("500"))
        #expect(message.contains("provider"))
    }

    @Test("Network timeouts explain that the provider request timed out")
    func networkTimeoutIsActionable() {
        let message = ErrorPresenter.message(for: URLError(.timedOut))

        #expect(message.contains("timed out"))
    }
}
