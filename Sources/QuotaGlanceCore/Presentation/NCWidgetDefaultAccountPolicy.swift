import Foundation

public enum NCWidgetDefaultAccountPolicy {
    public static func clearingDefaultIfNeeded(
        preferences: AppPreferences,
        deletedAccountID: UUID
    ) -> AppPreferences {
        guard preferences.notificationCenterDefaultAccountID == deletedAccountID else {
            return preferences
        }

        var updatedPreferences = preferences
        updatedPreferences.notificationCenterDefaultAccountID = nil
        return updatedPreferences
    }
}
