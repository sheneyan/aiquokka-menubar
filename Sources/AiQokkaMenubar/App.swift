import AppKit
import SwiftUI

@MainActor
@main
struct AiQokkaMenubarApp: App {
    @StateObject private var store: UsageStore
    @StateObject private var displayMode: DisplayModeSettings
    @StateObject private var alertCoordinator: UsageAlertCoordinator
    @StateObject private var ntfySettings: UsageNtfySettings
    private let controller: StandaloneWindowController

    init() {
        let runner = UsageCommandRunner()
        let decoder = UsageYAMLDecoder()
        let alertCoordinator = UsageAlertCoordinator()
        let ntfySettings = UsageNtfySettings()
        let milestoneCoordinator = UsageMilestoneCoordinator(
            configurationProvider: { ntfySettings.configuration }
        )
        let store = UsageStore(loader: {
            let yaml = try await runner.fetchYAML()
            return try decoder.decode(yaml: yaml)
        }, didLoadSnapshot: { snapshot in
            await alertCoordinator.process(snapshot: snapshot)
            await milestoneCoordinator.process(snapshot: snapshot)
        })
        let displayMode = DisplayModeSettings()
        _store = StateObject(wrappedValue: store)
        _displayMode = StateObject(wrappedValue: displayMode)
        _alertCoordinator = StateObject(wrappedValue: alertCoordinator)
        _ntfySettings = StateObject(wrappedValue: ntfySettings)
        let controller = StandaloneWindowController(
            store: store,
            displayMode: displayMode,
            alertCoordinator: alertCoordinator,
            ntfySettings: ntfySettings
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
                ntfySettings: ntfySettings,
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
        statusPresentation.symbolName
    }

    private var statusColor: MenuBarStatusColor {
        statusPresentation.color
    }

    private var statusPresentation: MenuBarStatusPresentation {
        MenuBarStatusPresentation(
            snapshot: store.snapshot,
            lastError: store.lastError,
            severity: alertCoordinator.highestSeverity
        )
    }

    private var statusImage: NSImage? {
        MenuBarStatusIcon.image(systemName: statusSymbol, color: statusColor)
    }

    private func percentText(_ percent: Double) -> String {
        String(format: "%.0f%%", percent)
    }
}
