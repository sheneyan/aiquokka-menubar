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
    static let defaultStepPercent = UsageNtfyConfiguration.defaultMilestoneStepPercent

    let stepPercent: Int

    init(stepPercent: Int = Self.defaultStepPercent) {
        self.stepPercent = UsageNtfyConfiguration.normalizedMilestoneStep(stepPercent)
    }

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

                let milestonePercent = Int(floor(usedPercent / Double(stepPercent))) * stepPercent
                guard milestonePercent >= stepPercent else { return nil }

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
    static let lastStepPercentKey = "aiquokka.usageMilestone.lastStepPercent"

    private struct StoredState: Codable {
        var resetDate: Date?
        var highestMilestone: Int
        var stepPercent: Int?
    }

    private let userDefaults: UserDefaults
    private var states: [String: StoredState]
    private var lastConfiguredStep: Int?

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        if let data = userDefaults.data(forKey: Self.userDefaultsKey),
           let decoded = try? JSONDecoder().decode([String: StoredState].self, from: data) {
            self.states = decoded
        } else {
            self.states = [:]
        }
        if let storedStep = (userDefaults.object(forKey: Self.lastStepPercentKey) as? NSNumber)?.intValue {
            self.lastConfiguredStep = UsageNtfyConfiguration.normalizedMilestoneStep(storedStep)
        } else {
            self.lastConfiguredStep = nil
        }
    }

    func highestSent(for milestone: UsageQuotaMilestone) -> Int {
        states[stateKey(for: milestone)]?.highestMilestone ?? 0
    }

    func updateStepPercent(_ stepPercent: Int) -> Bool {
        let normalizedStep = UsageNtfyConfiguration.normalizedMilestoneStep(stepPercent)
        let previousStep = lastConfiguredStep ?? UsageMilestoneEvaluator.defaultStepPercent
        let didChange = previousStep != normalizedStep

        if lastConfiguredStep != normalizedStep {
            lastConfiguredStep = normalizedStep
            userDefaults.set(normalizedStep, forKey: Self.lastStepPercentKey)
        }

        return didChange
    }

    func prepare(_ milestone: UsageQuotaMilestone, stepPercent: Int, stepDidChange: Bool = false) {
        let key = stateKey(for: milestone)
        let normalizedStep = UsageNtfyConfiguration.normalizedMilestoneStep(stepPercent)

        guard var current = states[key] else {
            states[key] = StoredState(
                resetDate: milestone.resetDate,
                highestMilestone: stepDidChange ? milestone.milestonePercent : 0,
                stepPercent: normalizedStep
            )
            persist()
            return
        }

        let previousStep = current.stepPercent ?? UsageMilestoneEvaluator.defaultStepPercent
        if !stepDidChange && previousStep == normalizedStep {
            guard current.stepPercent == nil else { return }
            current.stepPercent = normalizedStep
            states[key] = current
            persist()
            return
        }

        // Changing the interval establishes a new baseline at the current
        // usage level. This avoids backfilling a milestone the user already
        // passed before changing the setting.
        states[key] = StoredState(
            resetDate: milestone.resetDate,
            highestMilestone: milestone.milestonePercent,
            stepPercent: normalizedStep
        )
        persist()
    }

    func markSent(_ milestone: UsageQuotaMilestone) {
        let key = stateKey(for: milestone)
        var state = states[key] ?? StoredState(
            resetDate: milestone.resetDate,
            highestMilestone: 0,
            stepPercent: nil
        )
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
    private let stateStore: UsageMilestoneStateStore
    private let notificationClient: any UsageMilestoneNotificationClient
    private let configurationProvider: @MainActor () -> UsageNtfyConfiguration

    init(
        stateStore: UsageMilestoneStateStore = UsageMilestoneStateStore(),
        notificationClient: any UsageMilestoneNotificationClient = AgentNotifyUsageMilestoneNotificationClient(),
        configurationProvider: @escaping @MainActor () -> UsageNtfyConfiguration = { .disabled }
    ) {
        self.stateStore = stateStore
        self.notificationClient = notificationClient
        self.configurationProvider = configurationProvider
    }

    func process(snapshot: UsageSnapshot) async {
        let configuration = configurationProvider()
        guard configuration.isConfigured else { return }

        let stepDidChange = stateStore.updateStepPercent(configuration.milestoneStepPercent)
        let evaluator = UsageMilestoneEvaluator(stepPercent: configuration.milestoneStepPercent)
        for milestone in evaluator.evaluate(snapshot: snapshot) {
            stateStore.prepare(
                milestone,
                stepPercent: configuration.milestoneStepPercent,
                stepDidChange: stepDidChange
            )
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
