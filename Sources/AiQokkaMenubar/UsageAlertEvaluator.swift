import Foundation

struct UsageAlertEvaluator: Sendable {
    static let minimumUsageForPace: Double = 20
    static let paceMargin: Double = 15
    static let nearingLimit: Double = 80
    static let criticalLimit: Double = 95

    func evaluate(snapshot: UsageSnapshot, now: Date) -> UsageAlertEvaluation {
        let windows = snapshot.providers.flatMap { provider -> [UsageWindowAlertEvaluation] in
            guard provider.error == nil else { return [] }
            return provider.windows.compactMap { evaluate(provider: provider, window: $0, now: now) }
        }
        return UsageAlertEvaluation(windows: windows)
    }

    private func evaluate(provider: ProviderUsage, window: UsageWindow, now: Date) -> UsageWindowAlertEvaluation? {
        guard let used = window.effectiveUsedPercent, used.isFinite else {
            return nil
        }

        var activeKinds = Set<UsageAlertKind>()
        if used >= Self.nearingLimit {
            activeKinds.insert(.nearingLimit)
        }
        if used >= Self.criticalLimit {
            activeKinds.insert(.critical)
        }
        if isTooFast(usedPercent: used, window: window, now: now) {
            activeKinds.insert(.tooFast)
        }

        let selectedKind = activeKinds.max { lhs, rhs in
            lhs.priority < rhs.priority
        }
        let selectedAlert = selectedKind.map {
            UsageAlert(
                providerID: provider.id,
                providerName: provider.name,
                windowLabel: window.label,
                kind: $0,
                usedPercent: used,
                resetDate: window.resetDate
            )
        }

        return UsageWindowAlertEvaluation(
            providerID: provider.id,
            providerName: provider.name,
            windowLabel: window.label,
            resetDate: window.resetDate,
            activeKinds: activeKinds,
            selectedAlert: selectedAlert
        )
    }

    private func isTooFast(usedPercent: Double, window: UsageWindow, now: Date) -> Bool {
        guard usedPercent >= Self.minimumUsageForPace,
              let resetDate = window.resetDate,
              resetDate > now,
              let duration = durationSeconds(for: window.label)
        else { return false }

        let elapsed = duration - resetDate.timeIntervalSince(now)
        let timeProgress = min(max(elapsed / duration, 0), 1) * 100
        return usedPercent - timeProgress >= Self.paceMargin
    }

    private func durationSeconds(for label: String) -> TimeInterval? {
        let normalized = label.lowercased()
        if normalized.contains("5h") || normalized.contains("5-hour") || normalized.contains("5 hour") {
            return 5 * 60 * 60
        }
        if normalized == "daily" || normalized.contains("daily") || normalized == "day" {
            return 24 * 60 * 60
        }
        if normalized == "weekly" || normalized.contains("weekly") || normalized == "week" {
            return 7 * 24 * 60 * 60
        }
        return nil
    }
}
