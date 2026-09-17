import Foundation

struct UsageQuotaMilestone: Equatable, Hashable, Identifiable, Sendable {
    let providerID: String
    let providerName: String
    let plan: String?
    let windowLabel: String
    let usedPercent: Double
    let milestonePercent: Int
    let resetDate: Date?

    var id: String {
        let reset = resetDate.map { String($0.timeIntervalSinceReferenceDate) } ?? "none"
        return "aiquokka|quota|\(providerID)|\(windowLabel)|\(milestonePercent)|\(reset)"
    }

    var notificationTitle: String {
        "\(providerName) \(windowLabel) 用量达到 \(milestonePercent)%"
    }

    var notificationBody: String {
        let usage = String(format: "%.1f%%", usedPercent)
        let providerDescription = if let plan, !plan.isEmpty {
            "\(providerName)（\(plan)）"
        } else {
            providerName
        }

        guard let resetDate else {
            return "当前已使用 \(usage)，\(providerDescription)\(windowLabel) 窗口没有可用的重置时间。"
        }
        let reset = DateFormatter.localizedString(from: resetDate, dateStyle: .short, timeStyle: .short)
        return "当前已使用 \(usage)，\(providerDescription)\(windowLabel) 窗口预计于 \(reset) 恢复。"
    }
}

struct UsageMilestoneEvaluator: Sendable {
    static let stepPercent = 10

    func evaluate(snapshot: UsageSnapshot) -> [UsageQuotaMilestone] {
        snapshot.providers.flatMap { provider -> [UsageQuotaMilestone] in
            guard provider.error == nil else { return [] }
            return provider.windows.compactMap { window in
                guard let usedPercent = window.usedPercent,
                      usedPercent.isFinite,
                      (0...100).contains(usedPercent)
                else {
                    return nil
                }

                let milestonePercent = Int(floor(usedPercent / Double(Self.stepPercent))) * Self.stepPercent
                guard milestonePercent >= Self.stepPercent else { return nil }

                return UsageQuotaMilestone(
                    providerID: provider.id,
                    providerName: provider.name,
                    plan: provider.plan,
                    windowLabel: window.label,
                    usedPercent: usedPercent,
                    milestonePercent: milestonePercent,
                    resetDate: window.resetDate
                )
            }
        }
    }
}

@MainActor
final class UsageMilestoneStateStore {
    static let userDefaultsKey = "aiquokka.usageMilestone.sentStates"

    private struct StoredState: Codable {
        var resetDate: Date?
        var highestMilestone: Int
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

    func highestSent(for milestone: UsageQuotaMilestone) -> Int {
        states[stateKey(for: milestone)]?.highestMilestone ?? 0
    }

    func markSent(_ milestone: UsageQuotaMilestone) {
        let key = stateKey(for: milestone)
        var state = states[key] ?? StoredState(resetDate: milestone.resetDate, highestMilestone: 0)
        state.highestMilestone = max(state.highestMilestone, milestone.milestonePercent)
        states[key] = state
        persist()
    }

    private func stateKey(for milestone: UsageQuotaMilestone) -> String {
        let reset = milestone.resetDate.map { String($0.timeIntervalSinceReferenceDate) } ?? "none"
        return "\(milestone.providerID)\u{1F}\(milestone.windowLabel)\u{1F}\(reset)"
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(states) else { return }
        userDefaults.set(data, forKey: Self.userDefaultsKey)
    }
}

@MainActor
protocol UsageMilestoneNotificationClient: AnyObject {
    func send(
        _ milestone: UsageQuotaMilestone,
        configuration: UsageNtfyConfiguration
    ) async -> Bool
}

@MainActor
final class UsageMilestoneCoordinator {
    private let evaluator: UsageMilestoneEvaluator
    private let stateStore: UsageMilestoneStateStore
    private let notificationClient: any UsageMilestoneNotificationClient
    private let configurationProvider: @MainActor () -> UsageNtfyConfiguration

    init(
        evaluator: UsageMilestoneEvaluator = UsageMilestoneEvaluator(),
        stateStore: UsageMilestoneStateStore = UsageMilestoneStateStore(),
        notificationClient: any UsageMilestoneNotificationClient = AgentNotifyUsageMilestoneNotificationClient(),
        configurationProvider: @escaping @MainActor () -> UsageNtfyConfiguration = { .disabled }
    ) {
        self.evaluator = evaluator
        self.stateStore = stateStore
        self.notificationClient = notificationClient
        self.configurationProvider = configurationProvider
    }

    func process(snapshot: UsageSnapshot) async {
        let configuration = configurationProvider()
        guard configuration.isConfigured else { return }

        for milestone in evaluator.evaluate(snapshot: snapshot) {
            guard stateStore.highestSent(for: milestone) < milestone.milestonePercent else {
                continue
            }
            if await notificationClient.send(milestone, configuration: configuration) {
                stateStore.markSent(milestone)
            }
        }
    }
}

extension UsageNtfyConfiguration {
    static let disabled = UsageNtfyConfiguration(
        isEnabled: false,
        executablePath: "",
        configPath: ""
    )
}
