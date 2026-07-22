import Foundation
import QuotaGlanceCore
import UserNotifications

enum NotificationPermissionState: Equatable {
    case notDetermined
    case denied
    case authorized
}

@MainActor
final class NotificationService {
    private let center = UNUserNotificationCenter.current()

    func permissionState() async -> NotificationPermissionState {
        let settings = await center.notificationSettings()
        return switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            .authorized
        case .denied:
            .denied
        case .notDetermined:
            .notDetermined
        @unknown default:
            .denied
        }
    }

    func requestAuthorization() async -> NotificationPermissionState {
        do {
            _ = try await center.requestAuthorization(options: [.alert, .sound])
        } catch {
            return .denied
        }
        return await permissionState()
    }

    func sendLowBalance(
        account: Account,
        remaining: Money
    ) async throws {
        let content = UNMutableNotificationContent()
        content.title = "Low Balance: \(account.displayName)"
        content.body = "Remaining balance is \(MoneyFormatter.string(remaining))."
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "low-balance-\(account.id.uuidString)",
            content: content,
            trigger: nil
        )
        try await center.add(request)
    }
}
