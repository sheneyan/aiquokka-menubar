import Foundation

struct UsageSnapshot: Equatable, Sendable {
    let providers: [ProviderUsage]
    let fetchedAt: Date

    var highestUsagePercent: Double? {
        providers.compactMap(\.highestUsagePercent).max()
    }

    init(providers: [ProviderUsage], fetchedAt: Date) {
        self.providers = providers.sorted { $0.id.localizedStandardCompare($1.id) == .orderedAscending }
        self.fetchedAt = fetchedAt
    }
}

struct ProviderUsage: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let plan: String?
    let error: String?
    let windows: [UsageWindow]
    let extras: [UsageExtra]

    var highestUsagePercent: Double? {
        windows.compactMap(\.usedPercent).max()
    }

    var primaryWindow: UsageWindow? {
        windows.max { ($0.usedPercent ?? -1) < ($1.usedPercent ?? -1) }
    }
}

struct UsageWindow: Equatable, Sendable {
    let label: String
    let usedPercent: Double?
    let resetDate: Date?
    let resetText: String?
}

struct UsageExtra: Equatable, Sendable {
    let label: String
    let value: String
}
