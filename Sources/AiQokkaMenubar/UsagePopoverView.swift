import AppKit
import Foundation
import SwiftUI

// Both surfaces intentionally share complete content and behavior; keep this semantic
// distinction for entry-point clarity and future surface-specific differences.
internal enum UsageSurface {
    case menuBar
    case standaloneWindow
}

struct UsagePopoverView: View {
    @ObservedObject var store: UsageStore
    @ObservedObject var displayMode: DisplayModeSettings
    @ObservedObject var alertCoordinator: UsageAlertCoordinator
    let surface: UsageSurface
    let onDisplayModeChanged: (DisplayMode) -> Void

    private let maxContentHeight: CGFloat = 560

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider()

            if alertCoordinator.notificationAuthorizationState.shouldShowBanner {
                notificationPermissionSection
                Divider()
            }

            if let snapshot = store.snapshot {
                providerList(snapshot)
            } else if store.isRefreshing {
                emptyState(
                    systemImage: "arrow.clockwise",
                    title: "正在读取 aiquokka",
                    message: "首次读取可能需要几秒钟。"
                )
            } else {
                emptyState(
                    systemImage: "exclamationmark.triangle",
                    title: "暂无数据",
                    message: store.lastError ?? "还没有成功读取 aiquokka。"
                )
            }

            Divider()
            displayModePicker
            footer
        }
        .frame(width: 380)
        .fixedSize(horizontal: false, vertical: true)
        .background(.background)
        .task {
            await alertCoordinator.refreshAuthorizationState()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Label("aiquokka", systemImage: "gauge.with.dots.needle.67percent")
                    .font(.headline)
                Spacer()
                Button {
                    Task { await store.refresh() }
                } label: {
                    if store.isRefreshing {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                }
                .buttonStyle(.borderless)
                .help("立即刷新")
                .disabled(store.isRefreshing)
            }

            if let lastUpdated = store.lastUpdated {
                Text("更新于 \(dateText(lastUpdated))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("等待首次更新")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let lastError = store.lastError {
                Label(
                    store.snapshot == nil ? lastError : "上次刷新失败：\(lastError)",
                    systemImage: "exclamationmark.triangle.fill"
                )
                .font(.caption)
                .foregroundStyle(.orange)
                .textSelection(.enabled)
            }
        }
        .padding(16)
    }

    private func providerList(_ snapshot: UsageSnapshot) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 10) {
                if snapshot.providers.isEmpty {
                    emptyState(
                        systemImage: "tray",
                        title: "没有已配置的 provider",
                        message: "请先在本机 CLI 中完成登录。"
                    )
                } else {
                    ForEach(snapshot.providers) { provider in
                        ProviderUsageSection(provider: provider)
                    }
                }
            }
            .padding(16)
        }
        .frame(maxHeight: maxContentHeight)
    }

    private var displayModePicker: some View {
        HStack(spacing: 12) {
            Text("显示方式")
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()

            Picker("显示方式", selection: Binding(
                get: { displayMode.mode },
                set: { newMode in
                    displayMode.mode = newMode
                    onDisplayModeChanged(newMode)
                }
            )) {
                ForEach(DisplayMode.allCases) { mode in
                    Text(mode.title)
                        .tag(mode)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private var notificationPermissionSection: some View {
        switch alertCoordinator.notificationAuthorizationState {
        case .notDetermined:
            notificationCard(
                systemImage: "bell.badge",
                title: "开启用量提醒",
                message: "点击“开启”后，macOS 会弹出通知授权提示。",
                actionTitle: "开启",
                action: requestAuthorization
            )
        case .denied:
            notificationCard(
                systemImage: "bell.slash",
                title: "用量提醒未开启",
                message: "请在系统设置中打开 aiquokka 的“允许通知”。",
                actionTitle: "打开系统设置",
                action: openNotificationSettings
            )
        case .unavailable(let detail):
            notificationCard(
                systemImage: "exclamationmark.triangle",
                title: "通知暂不可用",
                message: detail.isEmpty ? "macOS 没有接受这个 App 的通知请求。" : detail,
                actionTitle: "打开系统设置",
                action: openNotificationSettings
            )
        case .unknown, .authorized:
            EmptyView()
        }
    }

    private func notificationCard(
        systemImage: String,
        title: String,
        message: String,
        actionTitle: String,
        action: @escaping () -> Void
    ) -> some View {
        UsageNotificationCard(
            systemImage: systemImage,
            title: title,
            message: message,
            actionTitle: actionTitle,
            isRequesting: alertCoordinator.isRequestingAuthorization,
            action: action
        )
    }

    private func requestAuthorization() {
        Task {
            await alertCoordinator.requestAuthorization()
        }
    }

    private func openNotificationSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    private func emptyState(systemImage: String, title: String, message: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.title2)
                .foregroundStyle(.secondary)
            Text(title)
                .font(.headline)
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .textSelection(.enabled)
            if store.snapshot == nil && !store.isRefreshing {
                Button("重试") {
                    Task { await store.refresh() }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(24)
    }

    private var footer: some View {
        HStack {
            Text("每 60 秒自动刷新")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Spacer()
            Button("退出") {
                NSApplication.shared.terminate(nil)
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private func dateText(_ date: Date) -> String {
        DateFormatter.localizedString(from: date, dateStyle: .short, timeStyle: .short)
    }
}

struct UsageNotificationCard: View {
    let systemImage: String
    let title: String
    let message: String
    let actionTitle: String
    let isRequesting: Bool
    let action: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: systemImage)
                .font(.title3)
                .foregroundStyle(.orange)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .layoutPriority(1)

            if isRequesting {
                ProgressView()
                    .controlSize(.small)
            } else {
                Button(actionTitle, action: action)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 10))
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}

private struct ProviderUsageSection: View {
    let provider: ProviderUsage

    var body: some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 10) {
                if let error = provider.error {
                    Label("读取失败", systemImage: "exclamationmark.triangle.fill")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.orange)
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                } else {
                    ForEach(provider.windows.indices, id: \.self) { index in
                        UsageWindowRow(window: provider.windows[index])
                    }
                }

                if !provider.extras.isEmpty {
                    Divider()
                    ForEach(provider.extras.indices, id: \.self) { index in
                        KeyValueRow(label: provider.extras[index].label, value: provider.extras[index].value)
                    }
                }
            }
            .padding(.top, 8)
        } label: {
            ProviderSummaryRow(provider: provider)
        }
        .padding(12)
        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 10))
    }
}

private struct ProviderSummaryRow: View {
    let provider: ProviderUsage

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(provider.name)
                    .font(.headline)
                if let plan = provider.plan, !plan.isEmpty {
                    Text(plan)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.secondary.opacity(0.12), in: Capsule())
                }
                Spacer()
                if let highestUsage = provider.highestUsagePercent {
                    Text(percentText(highestUsage))
                        .font(.subheadline.weight(.semibold))
                        .monospacedDigit()
                }
            }

            if let error = provider.error {
                Label("读取失败：\(error)", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .lineLimit(3)
                    .textSelection(.enabled)
            } else if let highestUsage = provider.highestUsagePercent {
                ProgressView(value: max(0, min(highestUsage, 100)), total: 100)
                    .tint(quotaProgressColor(for: highestUsage))
            } else {
                Text("没有可用的使用率窗口")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let primaryWindow = provider.primaryWindow {
                Text(resetSummary(for: primaryWindow))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func percentText(_ percent: Double) -> String {
        String(format: "%.1f%%", percent)
    }

    private func resetSummary(for window: UsageWindow) -> String {
        guard let resetDate = window.resetDate else {
            return window.resetText.map { "重置：\($0)" } ?? "没有重置时间"
        }
        let relative = RelativeDateTimeFormatter().localizedString(for: resetDate, relativeTo: Date())
        let absolute = DateFormatter.localizedString(from: resetDate, dateStyle: .short, timeStyle: .short)
        return "\(window.label) · \(relative)（\(absolute)）"
    }
}

private struct UsageWindowRow: View {
    let window: UsageWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(window.label)
                    .font(.subheadline.weight(.medium))
                Spacer()
                if let usedPercent = window.usedPercent {
                    Text(String(format: "%.1f%%", usedPercent))
                        .monospacedDigit()
                } else {
                    Text("—")
                        .foregroundStyle(.secondary)
                }
            }
            if let usedPercent = window.usedPercent {
                ProgressView(value: max(0, min(usedPercent, 100)), total: 100)
                    .tint(quotaProgressColor(for: usedPercent))
            }
            if let resetDate = window.resetDate {
                Text("重置：\(DateFormatter.localizedString(from: resetDate, dateStyle: .short, timeStyle: .short))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if let resetText = window.resetText {
                Text("重置：\(resetText)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private func quotaProgressColor(for usedPercent: Double) -> Color {
    switch UsageQuotaLevel(usedPercent: usedPercent) {
    case .healthy:
        return .green
    case .warning:
        return .yellow
    case .critical:
        return .red
    }
}

private struct KeyValueRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer(minLength: 12)
            Text(value)
                .font(.caption)
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
        }
    }
}
