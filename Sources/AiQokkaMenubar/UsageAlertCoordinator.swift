import Combine
import Foundation

@MainActor
final class UsageAlertCoordinator: ObservableObject {
    private let evaluator: UsageAlertEvaluator
    private let stateStore: UsageAlertStateStore
    private let notificationClient: any UsageNotificationClient

    @Published private(set) var highestSeverity: UsageAlertSeverity = .normal
    @Published private(set) var notificationAuthorizationState: UsageNotificationAuthorizationState = .unknown
    @Published private(set) var isRequestingAuthorization = false

    init(
        evaluator: UsageAlertEvaluator = UsageAlertEvaluator(),
        stateStore: UsageAlertStateStore = UsageAlertStateStore(),
        notificationClient: any UsageNotificationClient = SystemUsageNotificationClient()
    ) {
        self.evaluator = evaluator
        self.stateStore = stateStore
        self.notificationClient = notificationClient
    }

    func process(snapshot: UsageSnapshot, now: Date = Date()) async {
        let evaluation = evaluator.evaluate(snapshot: snapshot, now: now)
        highestSeverity = evaluation.highestSeverity

        for window in evaluation.windows {
            stateStore.reconcile(window)
        }

        for alert in evaluation.alerts where !stateStore.hasSent(alert) {
            if await notificationClient.send(alert) {
                stateStore.markSent(alert)
            }
        }
    }

    func refreshAuthorizationState() async {
        notificationAuthorizationState = await notificationClient.authorizationState()
    }

    @discardableResult
    func requestAuthorization() async -> UsageNotificationAuthorizationState {
        guard !isRequestingAuthorization else {
            return notificationAuthorizationState
        }

        isRequestingAuthorization = true
        defer { isRequestingAuthorization = false }

        let state = await notificationClient.requestAuthorization()
        notificationAuthorizationState = state
        return state
    }
}
