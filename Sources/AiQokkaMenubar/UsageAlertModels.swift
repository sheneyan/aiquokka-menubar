import Foundation

enum UsageAlertSeverity: Int, Comparable, Sendable {
    case normal = 0
    case warning = 1
    case critical = 2

    var systemImageName: String {
        "gauge.with.dots.needle.67percent"
    }

    static func < (lhs: UsageAlertSeverity, rhs: UsageAlertSeverity) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

enum UsageAlertKind: String, CaseIterable, Codable, Hashable, Sendable {
    case tooFast
    case nearingLimit
    case critical

    var severity: UsageAlertSeverity {
        self == .critical ? .critical : .warning
    }

    var priority: Int {
        switch self {
        case .tooFast: return 1
        case .nearingLimit: return 2
        case .critical: return 3
        }
    }

    var displayTitle: String {
        switch self {
        case .tooFast: return "消耗速度较快"
        case .nearingLimit: return "即将接近上限"
        case .critical: return "用量即将耗尽"
        }
    }
}

struct UsageAlert: Equatable, Hashable, Identifiable, Sendable {
    let providerID: String
    let providerName: String
    let windowLabel: String
    let kind: UsageAlertKind
    let usedPercent: Double
    let resetDate: Date?

    var id: String {
        let reset = resetDate.map { String($0.timeIntervalSinceReferenceDate) } ?? "none"
        return "aiquokka|\(providerID)|\(windowLabel)|\(kind.rawValue)|\(reset)"
    }

    var notificationTitle: String {
        "\(providerName) \(windowLabel) \(kind.displayTitle)"
    }

    var notificationBody: String {
        let percent = String(format: "%.1f%%", usedPercent)
        guard let resetDate else { return "当前使用率 \(percent)。" }
        let reset = DateFormatter.localizedString(from: resetDate, dateStyle: .short, timeStyle: .short)
        return "当前使用率 \(percent)，预计于 \(reset) 恢复。"
    }
}

struct UsageWindowAlertEvaluation: Equatable, Sendable {
    let providerID: String
    let providerName: String
    let windowLabel: String
    let resetDate: Date?
    let activeKinds: Set<UsageAlertKind>
    let selectedAlert: UsageAlert?
}

struct UsageAlertEvaluation: Equatable, Sendable {
    let windows: [UsageWindowAlertEvaluation]

    var alerts: [UsageAlert] {
        windows.compactMap(\.selectedAlert)
    }

    var highestSeverity: UsageAlertSeverity {
        alerts.map { $0.kind.severity }.max() ?? .normal
    }
}
