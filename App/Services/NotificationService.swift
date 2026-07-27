import Foundation
import QuotaGlanceCore
import UserNotifications

enum NotificationPermissionState: Equatable, Sendable {
    case notDetermined
    case denied
    case authorized
}

@MainActor
final class NotificationService {
    func permissionState() async -> NotificationPermissionState {
        await Self.currentPermissionState()
    }

    func requestAuthorization() async -> NotificationPermissionState {
        if !(await Self.requestAuthorization()) {
            return .denied
        }
        return await Self.currentPermissionState()
    }

    func sendLowBalance(
        account: Account,
        remaining: Money
    ) async throws {
        try await Self.sendNotification(
            identifier: "low-balance-\(account.id.uuidString)",
            title: "Low Balance: \(account.displayName)",
            body: "Remaining balance is \(MoneyFormatter.string(remaining))."
        )
    }

    nonisolated private static func currentPermissionState() async -> NotificationPermissionState {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
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

    nonisolated private static func requestAuthorization() async -> Bool {
        do {
            return try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound])
        } catch {
            return false
        }
    }

    nonisolated private static func sendNotification(
        identifier: String,
        title: String,
        body: String
    ) async throws {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: nil
        )
        try await UNUserNotificationCenter.current().add(request)
    }
}
