import AppKit
import SwiftUI

@MainActor
@main
struct AiQokkaMenubarApp: App {
    @StateObject private var store: UsageStore
    @StateObject private var displayMode: DisplayModeSettings
    @StateObject private var alertCoordinator: UsageAlertCoordinator
    private let controller: StandaloneWindowController

    init() {
        let runner = UsageCommandRunner()
        let decoder = UsageYAMLDecoder()
        let alertCoordinator = UsageAlertCoordinator()
        let store = UsageStore(loader: {
            let yaml = try await runner.fetchYAML()
            return try decoder.decode(yaml: yaml)
        }, didLoadSnapshot: { snapshot in
            await alertCoordinator.process(snapshot: snapshot)
        })
        let displayMode = DisplayModeSettings()
        _store = StateObject(wrappedValue: store)
        _displayMode = StateObject(wrappedValue: displayMode)
        _alertCoordinator = StateObject(wrappedValue: alertCoordinator)
        let controller = StandaloneWindowController(
            store: store,
            displayMode: displayMode,
            alertCoordinator: alertCoordinator
        )
        self.controller = controller
        store.startAutoRefresh()

        if displayMode.mode == .standaloneWindow {
            DispatchQueue.main.async {
                controller.show()
            }
        }
    }

    var body: some Scene {
        MenuBarExtra {
            UsagePopoverView(
                store: store,
                displayMode: displayMode,
                alertCoordinator: alertCoordinator,
                surface: .menuBar,
                onDisplayModeChanged: { mode in
                    if mode == .standaloneWindow {
                        controller.show()
                    } else {
                        controller.close()
                    }
                }
            )
        } label: {
            MenuBarSummaryView(store: store, alertCoordinator: alertCoordinator)
        }
        .menuBarExtraStyle(.window)
    }
}

private struct MenuBarSummaryView: View {
    @ObservedObject var store: UsageStore
    @ObservedObject var alertCoordinator: UsageAlertCoordinator

    var body: some View {
        HStack(spacing: 4) {
            if let statusImage {
                Image(nsImage: statusImage)
                    .renderingMode(.original)
            } else {
                Image(systemName: statusSymbol)
            }

            if store.isRefreshing && store.snapshot == nil {
                ProgressView()
                    .controlSize(.small)
            } else if let highestUsage = store.snapshot?.highestUsagePercent {
                Text(percentText(highestUsage))
                    .monospacedDigit()
            }
        }
        .accessibilityLabel("aiquokka usage")
    }

    private var statusSymbol: String {
        if store.snapshot == nil && store.lastError != nil {
            return "exclamationmark.triangle"
        }
        return alertCoordinator.highestSeverity.systemImageName
    }

    private var statusColor: MenuBarStatusColor {
        if store.snapshot == nil && store.lastError != nil {
            return .orange
        }

        switch alertCoordinator.highestSeverity {
        case .normal: return .green
        case .warning: return .yellow
        case .critical: return .red
        }
    }

    private var statusImage: NSImage? {
        MenuBarStatusIcon.image(systemName: statusSymbol, color: statusColor)
    }

    private func percentText(_ percent: Double) -> String {
        String(format: "%.0f%%", percent)
    }
}
