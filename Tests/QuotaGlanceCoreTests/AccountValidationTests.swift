import Foundation
import Testing
@testable import QuotaGlanceCore

@Suite("Account validation")
struct AccountValidationTests {
    @Test("Display name and API key are trimmed and required")
    func requiredFieldsAreTrimmed() throws {
        let draft = AccountDraft(
            displayName: "  Primary  ",
            apiKey: "  test-key  ",
            provider: .deepSeek,
            isEnabled: true,
            lowBalanceThresholdText: ""
        )

        let validated = try AccountValidator.validate(
            draft: draft,
            existingAccounts: []
        )

        #expect(validated.displayName == "Primary")
        #expect(validated.apiKey == "test-key")
        #expect(validated.provider == .deepSeek)
        #expect(validated.lowBalanceThreshold == nil)

        var emptyName = draft
        emptyName.displayName = "   "
        #expect(throws: AccountValidationError.emptyDisplayName) {
            try AccountValidator.validate(draft: emptyName, existingAccounts: [])
        }

        var emptyKey = draft
        emptyKey.apiKey = "\n\t"
        #expect(throws: AccountValidationError.emptyAPIKey) {
            try AccountValidator.validate(draft: emptyKey, existingAccounts: [])
        }
    }

    @Test("Twenty accounts are allowed while a twenty-first is rejected")
    func maximumTwentyAccounts() throws {
        let firstFive = (1...5).map { Account(displayName: "Account \($0)") }
        let sixth = try AccountValidator.validate(
            draft: AccountDraft(
                displayName: "Account 6",
                apiKey: "test-key",
                isEnabled: true,
                lowBalanceThresholdText: ""
            ),
            existingAccounts: firstFive
        )
        #expect(sixth.displayName == "Account 6")

        let accounts = (1...20).map { Account(displayName: "Account \($0)") }
        let draft = AccountDraft(
            displayName: "Account 21",
            apiKey: "test-key",
            isEnabled: true,
            lowBalanceThresholdText: ""
        )

        #expect(throws: AccountValidationError.maximumAccountsReached) {
            try AccountValidator.validate(draft: draft, existingAccounts: accounts)
        }

        let edited = try AccountValidator.validate(
            draft: AccountDraft(
                displayName: accounts[0].displayName,
                apiKey: "replacement-key",
                isEnabled: true,
                lowBalanceThresholdText: ""
            ),
            existingAccounts: accounts,
            editingAccountID: accounts[0].id
        )
        #expect(edited.displayName == "Account 1")
    }

    @Test("Duplicate names ignore surrounding whitespace and letter case")
    func duplicateNamesAreRejected() {
        let accounts = [Account(displayName: "Primary")]
        let draft = AccountDraft(
            displayName: " primary ",
            apiKey: "test-key",
            isEnabled: true,
            lowBalanceThresholdText: ""
        )

        #expect(throws: AccountValidationError.duplicateDisplayName) {
            try AccountValidator.validate(draft: draft, existingAccounts: accounts)
        }
    }

    @Test("Threshold must be a non-negative Decimal")
    func thresholdMustBeNonNegativeDecimal() throws {
        let base = AccountDraft(
            displayName: "Primary",
            apiKey: "test-key",
            isEnabled: true,
            lowBalanceThresholdText: "12.345678"
        )

        let validated = try AccountValidator.validate(
            draft: base,
            existingAccounts: []
        )
        #expect(validated.lowBalanceThreshold == Decimal(string: "12.345678"))

        for value in ["-1", "not-a-number"] {
            var invalid = base
            invalid.lowBalanceThresholdText = value
            #expect(throws: AccountValidationError.invalidThreshold) {
                try AccountValidator.validate(draft: invalid, existingAccounts: [])
            }
        }
    }

    @Test("Validation failure leaves the draft unchanged")
    func validationFailurePreservesDraft() {
        let draft = AccountDraft(
            displayName: "Primary",
            apiKey: "entered-key",
            isEnabled: true,
            lowBalanceThresholdText: "bad-value"
        )
        let original = draft

        #expect(throws: AccountValidationError.invalidThreshold) {
            try AccountValidator.validate(draft: draft, existingAccounts: [])
        }
        #expect(draft == original)
    }

    @Test("Editing may leave the API key empty to preserve the Keychain item")
    func editingMayPreserveExistingKey() throws {
        let account = Account(displayName: "Primary")
        let draft = AccountDraft(
            displayName: "Renamed",
            apiKey: "",
            isEnabled: true,
            lowBalanceThresholdText: ""
        )

        let validated = try AccountValidator.validate(
            draft: draft,
            existingAccounts: [account],
            editingAccountID: account.id
        )

        #expect(validated.apiKey == nil)
        #expect(validated.provider == .apiInfo)
    }

    @Test("Changing provider while editing requires a replacement key")
    func changingProviderRequiresReplacementKey() throws {
        let account = Account(displayName: "Primary", provider: .apiInfo)
        let changedProvider = AccountDraft(
            displayName: "Primary",
            apiKey: "",
            provider: .kimi,
            isEnabled: true,
            lowBalanceThresholdText: ""
        )

        #expect(throws: AccountValidationError.replacementKeyRequired) {
            try AccountValidator.validate(
                draft: changedProvider,
                existingAccounts: [account],
                editingAccountID: account.id
            )
        }

        var withReplacement = changedProvider
        withReplacement.apiKey = "replacement-key"
        let validated = try AccountValidator.validate(
            draft: withReplacement,
            existingAccounts: [account],
            editingAccountID: account.id
        )
        #expect(validated.provider == .kimi)
        #expect(validated.apiKey == "replacement-key")
    }

}
