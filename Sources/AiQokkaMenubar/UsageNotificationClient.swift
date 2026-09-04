import Foundation
import UserNotifications

enum UsageNotificationAuthorizationState: Equatable, Sendable {
    case unknown
    case notDetermined
    case authorized
    case denied
    case unavailable(String)

    var isAuthorized: Bool {
        self == .authorized
    }

    var shouldShowBanner: Bool {
        switch self {
        case .notDetermined, .denied, .unavailable:
            return true
        case .unknown, .authorized:
            return false
        }
    }

    var shouldShowSettings: Bool {
        switch self {
        case .denied, .unavailable:
            return true
        case .unknown, .notDetermined, .authorized:
            return false
        }
    }
}

@MainActor
protocol UsageNotificationClient: AnyObject {
    func authorizationState() async -> UsageNotificationAuthorizationState
    func requestAuthorization() async -> UsageNotificationAuthorizationState
    func send(_ alert: UsageAlert) async -> Bool
}

@MainActor
final class SystemUsageNotificationClient: UsageNotificationClient {
    private let center: UNUserNotificationCenter

    init(center: UNUserNotificationCenter = .current()) {
        self.center = center
    }

    func authorizationState() async -> UsageNotificationAuthorizationState {
        state(for: await center.notificationSettings().authorizationStatus)
    }

    func requestAuthorization() async -> UsageNotificationAuthorizationState {
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound])
            return granted ? .authorized : .denied
        } catch {
            return .unavailable(error.localizedDescription)
        }
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

    private func state(for status: UNAuthorizationStatus) -> UsageNotificationAuthorizationState {
        switch status {
        case .notDetermined:
            return .notDetermined
        case .authorized, .provisional, .ephemeral:
            return .authorized
        case .denied:
            return .denied
        @unknown default:
            return .unavailable("未知的通知授权状态")
        }
    }
}
