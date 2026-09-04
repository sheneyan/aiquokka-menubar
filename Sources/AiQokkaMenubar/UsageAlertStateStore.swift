import Foundation

@MainActor
final class UsageAlertStateStore {
    static let userDefaultsKey = "aiquokka.usageAlert.sentStates"

    private struct StoredState: Codable {
        var resetDate: Date?
        var sentKinds: Set<UsageAlertKind>
    }

    private let userDefaults: UserDefaults
    private var states: [String: StoredState]

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        if let data = userDefaults.data(forKey: Self.userDefaultsKey),
           let decoded = try? JSONDecoder().decode([String: StoredState].self, from: data) {
            self.states = decoded
        } else {
            self.states = [:]
        }
    }

    func reconcile(_ evaluation: UsageWindowAlertEvaluation) {
        let key = baseKey(providerID: evaluation.providerID, windowLabel: evaluation.windowLabel)
        var state = states[key] ?? StoredState(resetDate: evaluation.resetDate, sentKinds: [])
        if state.resetDate != evaluation.resetDate {
            state = StoredState(resetDate: evaluation.resetDate, sentKinds: [])
        }
        state.sentKinds.formIntersection(evaluation.activeKinds)
        states[key] = state
        persist()
    }

    func hasSent(_ alert: UsageAlert) -> Bool {
        let key = baseKey(providerID: alert.providerID, windowLabel: alert.windowLabel)
        guard let state = states[key], state.resetDate == alert.resetDate else { return false }
        return state.sentKinds.contains(alert.kind)
    }

    func markSent(_ alert: UsageAlert) {
        let key = baseKey(providerID: alert.providerID, windowLabel: alert.windowLabel)
        var state = states[key] ?? StoredState(resetDate: alert.resetDate, sentKinds: [])
        if state.resetDate != alert.resetDate {
            state = StoredState(resetDate: alert.resetDate, sentKinds: [])
        }
        state.sentKinds.insert(alert.kind)
        states[key] = state
        persist()
    }

    private func baseKey(providerID: String, windowLabel: String) -> String {
        "\(providerID)\u{1F}\(windowLabel)"
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(states) else { return }
        userDefaults.set(data, forKey: Self.userDefaultsKey)
    }
}
