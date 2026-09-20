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
        windows.compactMap(\.effectiveUsedPercent).max()
    }

    var primaryWindow: UsageWindow? {
        if let usageWindow = windows.max(by: { ($0.effectiveUsedPercent ?? -1) < ($1.effectiveUsedPercent ?? -1) }),
           usageWindow.effectiveUsedPercent != nil {
            return usageWindow
        }
        return windows.first(where: { $0.remaining != nil }) ?? windows.first
    }

    var balanceSummaryText: String? {
        guard highestUsagePercent == nil else { return nil }

        let usd = windows.first { $0.currency?.uppercased() == "USD" }?.remaining
        let cny = windows.first {
            ["CNY", "RMB"].contains($0.currency?.uppercased() ?? "")
        }?.remaining
        let values = [
            usd.map { String(format: "$%.2f", $0) },
            cny.map { String(format: "¥%.2f", $0) }
        ].compactMap { $0 }
        return values.isEmpty ? nil : values.joined(separator: " / ")
    }
}

struct UsageWindow: Equatable, Sendable {
    let label: String
    let usedPercent: Double?
    let used: Double?
    let limit: Double?
    let remaining: Double?
    let currency: String?
    let resetDate: Date?
    let resetText: String?

    init(
        label: String,
        usedPercent: Double?,
        used: Double? = nil,
        limit: Double? = nil,
        remaining: Double? = nil,
        currency: String? = nil,
        resetDate: Date?,
        resetText: String?
    ) {
        self.label = label
        self.usedPercent = usedPercent
        self.used = used
        self.limit = limit
        self.remaining = remaining
        self.currency = currency
        self.resetDate = resetDate
        self.resetText = resetText
    }

    var effectiveUsedPercent: Double? {
        if let usedPercent, (0 ... 100).contains(usedPercent) {
            return usedPercent
        }
        guard let used, let limit, limit > 0 else { return nil }
        let percent = used / limit * 100
        return (0 ... 100).contains(percent) ? percent : nil
    }
}

struct UsageExtra: Equatable, Sendable {
    let label: String
    let value: String
}
