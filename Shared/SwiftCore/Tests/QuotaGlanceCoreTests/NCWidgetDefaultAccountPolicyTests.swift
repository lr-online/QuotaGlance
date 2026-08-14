import Foundation
import Testing
@testable import QuotaGlanceCore

@Suite("NC widget default account policy")
struct NCWidgetDefaultAccountPolicyTests {
    @Test("Deleting the default account clears the NC widget default")
    func deletingDefaultAccountClearsNCWidgetDefault() {
        let accountID = UUID()
        let preferences = AppPreferences(
            refreshInterval: .fiveMinutes,
            launchAtLogin: false,
            notificationCenterDefaultAccountID: accountID
        )

        let cleared = NCWidgetDefaultAccountPolicy.clearingDefaultIfNeeded(
            preferences: preferences,
            deletedAccountID: accountID
        )

        #expect(cleared.notificationCenterDefaultAccountID == nil)
    }

    @Test("Deleting a different account keeps the NC widget default")
    func deletingOtherAccountKeepsNCWidgetDefault() {
        let defaultID = UUID()
        let preferences = AppPreferences(
            refreshInterval: .fiveMinutes,
            launchAtLogin: false,
            notificationCenterDefaultAccountID: defaultID
        )

        let kept = NCWidgetDefaultAccountPolicy.clearingDefaultIfNeeded(
            preferences: preferences,
            deletedAccountID: UUID()
        )

        #expect(kept.notificationCenterDefaultAccountID == defaultID)
    }
}
