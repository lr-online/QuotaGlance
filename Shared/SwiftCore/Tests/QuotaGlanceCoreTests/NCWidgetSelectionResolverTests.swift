import Foundation
import Testing
@testable import QuotaGlanceCore

@Suite("NC widget selection resolver")
struct NCWidgetSelectionResolverTests {
    @Test("Use app default with no default account resolves to all accounts")
    func useAppDefaultWithNilDefault() {
        let selection = NCWidgetSelectionResolver.selection(
            choice: .useAppDefault,
            defaultAccountID: nil
        )
        #expect(selection == .allAccounts)
    }

    @Test("Use app default with default account resolves to that account")
    func useAppDefaultWithDefaultAccount() {
        let accountID = UUID()
        let selection = NCWidgetSelectionResolver.selection(
            choice: .useAppDefault,
            defaultAccountID: accountID
        )
        #expect(selection == .account(accountID))
    }

    @Test("All accounts choice resolves to all accounts regardless of default")
    func allAccountsChoiceIgnoresDefault() {
        let selection = NCWidgetSelectionResolver.selection(
            choice: .allAccounts,
            defaultAccountID: UUID()
        )
        #expect(selection == .allAccounts)
    }

    @Test("Specific account choice resolves to that account regardless of default")
    func accountChoiceIgnoresDefault() {
        let accountID = UUID()
        let selection = NCWidgetSelectionResolver.selection(
            choice: .account(accountID),
            defaultAccountID: UUID()
        )
        #expect(selection == .account(accountID))
    }
}
