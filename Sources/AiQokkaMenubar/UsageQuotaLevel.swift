import Foundation

enum UsageQuotaLevel: String, Sendable {
    case healthy
    case warning
    case critical

    init(usedPercent: Double) {
        switch usedPercent {
        case 80...:
            self = .critical
        case 60..<80:
            self = .warning
        default:
            self = .healthy
        }
    }
}
