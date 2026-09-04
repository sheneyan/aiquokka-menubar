import Combine
import Foundation

@MainActor
final class UsageAlertCoordinator: ObservableObject {
    private let evaluator: UsageAlertEvaluator
    private let stateStore: UsageAlertStateStore
    private let notificationClient: any UsageNotificationClient
    private var authorizationRequested = false

    @Published private(set) var highestSeverity: UsageAlertSeverity = .normal

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

        if !authorizationRequested {
            authorizationRequested = true
            await notificationClient.requestAuthorization()
        }

        for alert in evaluation.alerts where !stateStore.hasSent(alert) {
            if await notificationClient.send(alert) {
                stateStore.markSent(alert)
            }
        }
    }
}
