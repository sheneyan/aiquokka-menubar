import SwiftUI

@MainActor
@main
struct AiQokkaMenubarApp: App {
    @StateObject private var store: UsageStore

    init() {
        let runner = UsageCommandRunner()
        let decoder = UsageYAMLDecoder()
        let store = UsageStore(loader: {
            let yaml = try await runner.fetchYAML()
            return try decoder.decode(yaml: yaml)
        })
        _store = StateObject(wrappedValue: store)
        store.startAutoRefresh()
    }

    var body: some Scene {
        MenuBarExtra {
            UsagePopoverView(store: store)
        } label: {
            MenuBarSummaryView(store: store)
        }
        .menuBarExtraStyle(.window)
    }
}

private struct MenuBarSummaryView: View {
    @ObservedObject var store: UsageStore

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: store.snapshot == nil && store.lastError != nil
                ? "exclamationmark.triangle"
                : "gauge.with.dots.needle.67percent")

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

    private func percentText(_ percent: Double) -> String {
        String(format: "%.0f%%", percent)
    }
}
