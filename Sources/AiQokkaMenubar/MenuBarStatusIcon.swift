import AppKit

struct MenuBarStatusPresentation: Equatable, Sendable {
    let color: MenuBarStatusColor
    let symbolName: String

    init(
        snapshot: UsageSnapshot?,
        lastError: String?,
        severity: UsageAlertSeverity
    ) {
        symbolName = "gauge.with.dots.needle.67percent"

        if lastError != nil || snapshot?.providers.contains(where: { $0.error != nil }) == true {
            color = .red
        } else {
            switch severity {
            case .normal:
                color = .green
            case .warning:
                color = .yellow
            case .critical:
                color = .red
            }
        }
    }
}

enum MenuBarStatusColor: Equatable, Sendable {
    case green
    case yellow
    case red
    case orange

    var nsColor: NSColor {
        switch self {
        case .green:
            return .systemGreen
        case .yellow:
            return .systemYellow
        case .red:
            return .systemRed
        case .orange:
            return .systemOrange
        }
    }
}

enum MenuBarStatusIcon {
    static func image(systemName: String, color: MenuBarStatusColor) -> NSImage? {
        guard let baseImage = NSImage(
            systemSymbolName: systemName,
            accessibilityDescription: "aiquokka usage status"
        ) else {
            return nil
        }

        let configuration = NSImage.SymbolConfiguration(paletteColors: [color.nsColor])
        guard let image = baseImage.withSymbolConfiguration(configuration) else {
            return nil
        }

        image.isTemplate = false
        return image
    }
}
