import Foundation
import UserNotifications

@MainActor
protocol UsageNotificationClient: AnyObject {
    func requestAuthorization() async
    func send(_ alert: UsageAlert) async -> Bool
}

@MainActor
final class SystemUsageNotificationClient: UsageNotificationClient {
    private let center: UNUserNotificationCenter

    init(center: UNUserNotificationCenter = .current()) {
        self.center = center
    }

    func requestAuthorization() async {
        _ = try? await center.requestAuthorization(options: [.alert, .sound])
    }

    func send(_ alert: UsageAlert) async -> Bool {
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else {
            return false
        }

        let content = UNMutableNotificationContent()
        content.title = alert.notificationTitle
        content.body = alert.notificationBody
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: alert.id,
            content: content,
            trigger: nil
        )

        do {
            try await center.add(request)
            return true
        } catch {
            return false
        }
    }
}
