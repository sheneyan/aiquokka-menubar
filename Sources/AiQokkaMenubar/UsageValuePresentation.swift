import Foundation

struct UsageValuePresentation: Equatable, Sendable {
    let valueText: String
    let progressPercent: Double?
    let detailText: String?

    init(window: UsageWindow) {
        if let percent = window.effectiveUsedPercent {
            valueText = String(format: "%.1f%%", percent)
            progressPercent = percent
            if let used = window.used, let limit = window.limit {
                detailText = String(format: "%.2f / %.2f", used, limit)
            } else {
                detailText = nil
            }
            return
        }

        if let remaining = window.remaining {
            valueText = Self.amountText(remaining, currency: window.currency)
            progressPercent = nil
            detailText = nil
            return
        }

        valueText = "—"
        progressPercent = nil
        detailText = nil
    }

    private static func amountText(_ amount: Double, currency: String?) -> String {
        switch currency?.uppercased() {
        case "CNY", "RMB": return String(format: "¥%.2f", amount)
        case "USD": return String(format: "$%.2f", amount)
        case "EUR": return String(format: "€%.2f", amount)
        case "GBP": return String(format: "£%.2f", amount)
        case let code?: return String(format: "%.2f %@", amount, code)
        case nil: return String(format: "%.2f", amount)
        }
    }
}
