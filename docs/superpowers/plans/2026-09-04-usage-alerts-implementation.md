# aiquokka Usage Alerts Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add local, deduplicated macOS notifications and menu bar status indicators for usage windows that are consuming too quickly or approaching exhaustion.

**Architecture:** Keep `UsageStore` as the only source of fresh data from the local `aiquokka --yml` command. After each successful refresh, pass the snapshot through a pure `UsageAlertEvaluator`, reconcile per-window alert state in a `UserDefaults`-backed store, and send new events through an injected `UNUserNotificationCenter` adapter. The menu bar observes the same coordinator; the standalone window and popover keep sharing the existing store.

**Tech Stack:** Swift 6, SwiftUI, Combine `ObservableObject`, Foundation `UserDefaults`, macOS `UserNotifications`, XCTest, Swift Package Manager, macOS 13+.

---

## 实施状态（2026-09-05）

本计划的用量提醒功能已经落地到 `main`。后续修复记录如下：

- `bbd6a66`：通知授权改为显式用户操作；详情界面显示权限状态和“开启/打开系统设置”入口；构建脚本优先使用本机 Apple Development 签名。
- `c218a49`：通知权限卡片的长说明限制在剩余宽度内完整自动换行，卡片和独立窗口保持内容自适应高度；新增 `UsageNotificationCardLayoutTests`。
- 当前增量：菜单栏改用三色仪表盘状态图标；内容区进度条按剩余额度独立使用绿/黄/红，不受“消耗过快”提醒影响；整次刷新失败或任一 provider 读取失败时，菜单栏优先显示红色仪表盘。
- 当前验证：`swift test` 50/50 通过；`dist/aiquokka.app` 构建成功，`codesign --verify --deep --strict` 通过。
- 真实 macOS 的最后一步仍需在已解锁桌面上手动点击“开启”，确认系统授权弹窗；自动化 UI 验证不替代该人工授权步骤。

Task 3 中关于“首次成功快照自动请求授权”的早期示例已被本节记录的显式授权行为取代；实现以当前源码为准。

## File map

- Create `Sources/AiQokkaMenubar/UsageAlertModels.swift`: alert kinds, severity, alert payloads, and evaluator result value types with no SwiftUI or system-notification dependency.
- Create `Sources/AiQokkaMenubar/UsageAlertEvaluator.swift`: pure threshold and pace calculations, including safe recognition of known window durations.
- Create `Sources/AiQokkaMenubar/UsageAlertStateStore.swift`: persisted sent-kind state keyed by provider/window/reset identity; it stores no credentials or raw usage data.
- Create `Sources/AiQokkaMenubar/UsageNotificationClient.swift`: `UNUserNotificationCenter` adapter, authorization-state mapping, and the testable notification protocol.
- Create `Sources/AiQokkaMenubar/UsageAlertCoordinator.swift`: main-actor orchestration, deduplication, explicit authorization request, and published alert/permission state.
- Modify `Sources/AiQokkaMenubar/UsageStore.swift`: add an async success-only snapshot callback without changing loader, proxy, refresh interval, or error semantics.
- Modify `Sources/AiQokkaMenubar/App.swift`: construct one coordinator, connect it to the shared store, and expose its severity to the menu bar summary.
- Create `Tests/AiQokkaMenubarTests/UsageAlertEvaluatorTests.swift`: red-green tests for thresholds, pace, duration recognition, invalid data, and provider errors.
- Create `Tests/AiQokkaMenubarTests/UsageAlertStateStoreTests.swift`: isolated `UserDefaults` tests for persistence, rearming, reset identity, and data boundaries.
- Create `Tests/AiQokkaMenubarTests/UsageAlertCoordinatorTests.swift`: fake notification-client tests for authorization, deduplication, escalation, and retry behavior.
- Create `Tests/AiQokkaMenubarTests/UsageNotificationCardLayoutTests.swift`: fixed-width SwiftUI layout regression test for long permission text.
- Modify `Tests/AiQokkaMenubarTests/UsageStoreTests.swift`: verify the success callback runs only after a successful refresh.
- Do not modify `Package.swift` or `Sources/AiQokkaMenubar/Resources/Info.plist`; `UserNotifications` is part of the macOS SDK. The bundle script signs the assembled app when a local Apple Development identity is available.

## Domain contracts

Use these names and rules consistently across all tasks:

```swift
enum UsageAlertSeverity: Int, Comparable, Sendable {
    case normal = 0
    case warning = 1
    case critical = 2

    var systemImageName: String {
        switch self {
        case .normal: return "gauge.with.dots.needle.67percent"
        case .warning: return "bell.badge"
        case .critical: return "bell.badge.fill"
        }
    }
}

enum UsageAlertKind: String, CaseIterable, Codable, Hashable, Sendable {
    case tooFast
    case nearingLimit
    case critical
}

struct UsageAlert: Equatable, Hashable, Identifiable, Sendable {
    let providerID: String
    let providerName: String
    let windowLabel: String
    let kind: UsageAlertKind
    let usedPercent: Double
    let resetDate: Date?
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
    var alerts: [UsageAlert] { windows.compactMap(\.selectedAlert) }
    var highestSeverity: UsageAlertSeverity {
        alerts.map { $0.kind.severity }.max() ?? .normal
    }
}
```

The evaluator may find several active conditions for one window, but selects one alert for that refresh using priority `critical > nearingLimit > tooFast`. This prevents a first snapshot at 96% from producing three simultaneous notifications. The state store still retains sent kinds independently, so a normal progression from 80% to 95% can produce one warning and one critical notification.

## Task 1: Add the pure usage-alert evaluator

**Files:**
- Create: `Sources/AiQokkaMenubar/UsageAlertModels.swift`
- Create: `Sources/AiQokkaMenubar/UsageAlertEvaluator.swift`
- Test: `Tests/AiQokkaMenubarTests/UsageAlertEvaluatorTests.swift`

- [ ] **Step 1: Write failing evaluator tests**

Create fixed-time snapshots with `UsageWindow(label:usedPercent:resetDate:resetText:)`. Cover the user-approved boundaries and keep each test focused:

```swift
@testable import AiQokkaMenubar
import Foundation
import XCTest

final class UsageAlertEvaluatorTests: XCTestCase {
    private let evaluator = UsageAlertEvaluator()
    private let now = Date(timeIntervalSince1970: 1_000_000)

    func testUsageBelowTwentyPercentDoesNotTriggerPaceAlert() {
        let evaluation = evaluate(usedPercent: 19, label: "Weekly", resetAfter: 6 * day)

        XCTAssertTrue(evaluation.alerts.isEmpty)
    }

    func testWeeklyUsageFifteenPointsAheadOfClockTriggersTooFast() throws {
        let evaluation = evaluate(usedPercent: 30, label: "Weekly", resetAfter: 6 * day)

        let alert = try XCTUnwrap(evaluation.alerts.first)
        XCTAssertEqual(alert.kind, .tooFast)
    }

    func testPaceGapBelowFifteenPointsDoesNotTrigger() {
        let evaluation = evaluate(usedPercent: 29, label: "Weekly", resetAfter: 6 * day)

        XCTAssertTrue(evaluation.alerts.isEmpty)
    }

    func testEightyAndNinetyFivePercentSelectDifferentLevels() throws {
        let warning = try XCTUnwrap(evaluate(usedPercent: 80, label: "Weekly").alerts.first)
        let critical = try XCTUnwrap(evaluate(usedPercent: 95, label: "Weekly").alerts.first)

        XCTAssertEqual(warning.kind, .nearingLimit)
        XCTAssertEqual(critical.kind, .critical)
    }

    func testUnknownDurationDoesNotTriggerPaceAlert() {
        let evaluation = evaluate(usedPercent: 30, label: "Custom Window", resetAfter: 1 * day)

        XCTAssertTrue(evaluation.alerts.isEmpty)
    }

    func testMissingOrExpiredResetDoesNotTriggerPaceAlert() {
        let missingReset = evaluate(usedPercent: 30, label: "Weekly", resetAfter: nil)
        let expiredReset = evaluate(usedPercent: 30, label: "Weekly", resetAfter: -1)

        XCTAssertTrue(missingReset.alerts.isEmpty)
        XCTAssertTrue(expiredReset.alerts.isEmpty)
    }

    func testProviderErrorsDoNotTriggerAlerts() {
        let snapshot = UsageSnapshot(
            providers: [ProviderUsage(
                id: "codex",
                name: "Codex",
                plan: nil,
                error: "network error",
                windows: [UsageWindow(label: "Weekly", usedPercent: 95, resetDate: now.addingTimeInterval(6 * day), resetText: nil)],
                extras: []
            )],
            fetchedAt: now
        )

        XCTAssertTrue(evaluator.evaluate(snapshot: snapshot, now: now).alerts.isEmpty)
    }

    func testAlertSeverityExposesTheMenuBarSymbols() {
        XCTAssertEqual(UsageAlertSeverity.normal.systemImageName, "gauge.with.dots.needle.67percent")
        XCTAssertEqual(UsageAlertSeverity.warning.systemImageName, "bell.badge")
        XCTAssertEqual(UsageAlertSeverity.critical.systemImageName, "bell.badge.fill")
    }

    private var day: TimeInterval { 24 * 60 * 60 }

    private func evaluate(usedPercent: Double, label: String, resetAfter: TimeInterval? = 6 * 24 * 60 * 60) -> UsageAlertEvaluation {
        let resetDate = resetAfter.map { now.addingTimeInterval($0) }
        let window = UsageWindow(label: label, usedPercent: usedPercent, resetDate: resetDate, resetText: nil)
        let provider = ProviderUsage(id: "codex", name: "Codex", plan: "plus", error: nil, windows: [window], extras: [])
        let snapshot = UsageSnapshot(providers: [provider], fetchedAt: now)
        return evaluator.evaluate(snapshot: snapshot, now: now)
    }
}
```

- [ ] **Step 2: Run the evaluator tests and verify the missing implementation fails**

Run:

```bash
swift test --filter UsageAlertEvaluatorTests
```

Expected: compilation fails because the alert model and evaluator types do not exist. If the test target fails for an unrelated package or environment reason, fix only that test setup before proceeding; do not add production alert code yet.

- [ ] **Step 3: Implement the minimal alert model and evaluator**

Implement `UsageAlertModels.swift` with `UsageAlertSeverity` ordering, `UsageAlertKind` severity/priority, `UsageAlert` identity and notification text, and `UsageAlertEvaluation.highestSeverity`. The alert identity must include provider ID, window label, kind, and reset timestamp (or `none` when absent) so a new reset window is a new notification request.

Use this complete model implementation:

```swift
import Foundation

enum UsageAlertSeverity: Int, Comparable, Sendable {
    case normal = 0
    case warning = 1
    case critical = 2

    var systemImageName: String {
        switch self {
        case .normal: return "gauge.with.dots.needle.67percent"
        case .warning: return "bell.badge"
        case .critical: return "bell.badge.fill"
        }
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
```

Implement `UsageAlertEvaluator.swift` with these exact constants and behavior:

```swift
struct UsageAlertEvaluator: Sendable {
    static let minimumUsageForPace: Double = 20
    static let paceMargin: Double = 15
    static let nearingLimit: Double = 80
    static let criticalLimit: Double = 95

    func evaluate(snapshot: UsageSnapshot, now: Date) -> UsageAlertEvaluation {
        let windows = snapshot.providers.flatMap { provider -> [UsageWindowAlertEvaluation] in
            guard provider.error == nil else { return [] }
            return provider.windows.map { evaluate(provider: provider, window: $0, now: now) }
        }
        return UsageAlertEvaluation(windows: windows)
    }

    private func evaluate(provider: ProviderUsage, window: UsageWindow, now: Date) -> UsageWindowAlertEvaluation {
        guard let used = window.usedPercent, used.isFinite, (0...100).contains(used) else {
            return UsageWindowAlertEvaluation(providerID: provider.id, providerName: provider.name, windowLabel: window.label, resetDate: window.resetDate, activeKinds: [], selectedAlert: nil)
        }

        var activeKinds = Set<UsageAlertKind>()
        if used >= Self.nearingLimit { activeKinds.insert(.nearingLimit) }
        if used >= Self.criticalLimit { activeKinds.insert(.critical) }
        if isTooFast(usedPercent: used, window: window, now: now) { activeKinds.insert(.tooFast) }

        let selectedKind = activeKinds.max { $0.priority < $1.priority }
        let selectedAlert = selectedKind.map {
            UsageAlert(providerID: provider.id, providerName: provider.name, windowLabel: window.label, kind: $0, usedPercent: used, resetDate: window.resetDate)
        }
        return UsageWindowAlertEvaluation(providerID: provider.id, providerName: provider.name, windowLabel: window.label, resetDate: window.resetDate, activeKinds: activeKinds, selectedAlert: selectedAlert)
    }

    private func isTooFast(usedPercent: Double, window: UsageWindow, now: Date) -> Bool {
        guard usedPercent >= Self.minimumUsageForPace,
              let resetDate = window.resetDate,
              resetDate > now,
              let duration = durationSeconds(for: window.label)
        else { return false }

        let elapsed = duration - resetDate.timeIntervalSince(now)
        let timeProgress = min(max(elapsed / duration, 0), 1) * 100
        return usedPercent - timeProgress >= Self.paceMargin
    }

    private func durationSeconds(for label: String) -> TimeInterval? {
        let normalized = label.lowercased()
        if normalized.contains("5h") || normalized.contains("5-hour") || normalized.contains("5 hour") { return 5 * 60 * 60 }
        if normalized == "daily" || normalized.contains("daily") || normalized == "day" { return 24 * 60 * 60 }
        if normalized == "weekly" || normalized.contains("weekly") || normalized == "week" { return 7 * 24 * 60 * 60 }
        return nil
    }
}
```

Do not infer monthly duration, convert a balance into a percentage, or evaluate a provider error as zero usage. Keep reset dates that are present in the `UsageWindow` so notification text can include them.

- [ ] **Step 4: Run the evaluator tests and confirm they pass**

Run:

```bash
swift test --filter UsageAlertEvaluatorTests
```

Expected: all evaluator tests pass. Also run `swift test --filter UsageYAMLDecoderTests` to confirm no existing YAML behavior changed.

- [ ] **Step 5: Commit the evaluator**

```bash
git add Sources/AiQokkaMenubar/UsageAlertModels.swift Sources/AiQokkaMenubar/UsageAlertEvaluator.swift Tests/AiQokkaMenubarTests/UsageAlertEvaluatorTests.swift
git commit -m "feat: add usage alert evaluation"
```

## Task 2: Persist sent-alert state and rearm safely

**Files:**
- Create: `Sources/AiQokkaMenubar/UsageAlertStateStore.swift`
- Test: `Tests/AiQokkaMenubarTests/UsageAlertStateStoreTests.swift`

- [ ] **Step 1: Write failing state-store tests**

Use a unique `UserDefaults(suiteName:)` for each test. Verify that sent kinds survive a new store instance, that inactive kinds are rearmed, and that a new reset date starts clean:

```swift
@testable import AiQokkaMenubar
import Foundation
import XCTest

@MainActor
final class UsageAlertStateStoreTests: XCTestCase {
    func testSentAlertRemainsSuppressedAfterStoreReload() {
        let defaults = makeDefaults()
        let resetDate = Date(timeIntervalSince1970: 2_000)
        let alert = makeAlert(kind: .nearingLimit, resetDate: resetDate)
        let context = makeContext(resetDate: resetDate, activeKinds: [.nearingLimit])

        let first = UsageAlertStateStore(userDefaults: defaults)
        first.reconcile(context)
        first.markSent(alert)

        let second = UsageAlertStateStore(userDefaults: defaults)
        second.reconcile(context)

        XCTAssertTrue(second.hasSent(alert))
    }

    func testInactiveKindIsRearmedWhenUsageLeavesTheThreshold() {
        let defaults = makeDefaults()
        let resetDate = Date(timeIntervalSince1970: 2_000)
        let alert = makeAlert(kind: .nearingLimit, resetDate: resetDate)
        let store = UsageAlertStateStore(userDefaults: defaults)

        store.reconcile(makeContext(resetDate: resetDate, activeKinds: [.nearingLimit]))
        store.markSent(alert)
        store.reconcile(makeContext(resetDate: resetDate, activeKinds: []))

        XCTAssertFalse(store.hasSent(alert))
    }

    func testChangingResetDateAllowsTheSameKindAgain() {
        let defaults = makeDefaults()
        let oldReset = Date(timeIntervalSince1970: 2_000)
        let newReset = Date(timeIntervalSince1970: 3_000)
        let store = UsageAlertStateStore(userDefaults: defaults)

        let oldAlert = makeAlert(kind: .critical, resetDate: oldReset)
        store.reconcile(makeContext(resetDate: oldReset, activeKinds: [.critical]))
        store.markSent(oldAlert)

        let newAlert = makeAlert(kind: .critical, resetDate: newReset)
        store.reconcile(makeContext(resetDate: newReset, activeKinds: [.critical]))

        XCTAssertFalse(store.hasSent(newAlert))
    }

    func testStateStorageDoesNotContainCredentialsOrRawYAML() {
        let defaults = makeDefaults()
        let store = UsageAlertStateStore(userDefaults: defaults)
        let alert = UsageAlert(providerID: "codex", providerName: "Codex", windowLabel: "Weekly", kind: .critical, usedPercent: 95, resetDate: nil)

        store.reconcile(makeContext(resetDate: nil, activeKinds: [.critical]))
        store.markSent(alert)

        let data = try! XCTUnwrap(defaults.data(forKey: UsageAlertStateStore.userDefaultsKey))
        let saved = String(decoding: data, as: UTF8.self)
        XCTAssertFalse(saved.contains("DEEPSEEK_API_KEY"))
        XCTAssertFalse(saved.contains("api.deepseek.com"))
    }

    private func makeDefaults() -> UserDefaults {
        let name = "AiQokkaUsageAlertStateTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        addTeardownBlock { defaults.removePersistentDomain(forName: name) }
        return defaults
    }

    private func makeAlert(kind: UsageAlertKind, resetDate: Date?) -> UsageAlert {
        UsageAlert(providerID: "codex", providerName: "Codex", windowLabel: "Weekly", kind: kind, usedPercent: 95, resetDate: resetDate)
    }

    private func makeContext(resetDate: Date?, activeKinds: Set<UsageAlertKind>) -> UsageWindowAlertEvaluation {
        UsageWindowAlertEvaluation(providerID: "codex", providerName: "Codex", windowLabel: "Weekly", resetDate: resetDate, activeKinds: activeKinds, selectedAlert: nil)
    }
}
```

- [ ] **Step 2: Run the state-store tests and verify they fail for the missing type**

Run:

```bash
swift test --filter UsageAlertStateStoreTests
```

Expected: compilation fails because `UsageAlertStateStore` does not exist yet.

- [ ] **Step 3: Implement the `UserDefaults` state store**

Use a base key composed only of `providerID` and `windowLabel`, and store a Codable dictionary under `UsageAlertStateStore.userDefaultsKey`:

```swift
@MainActor
final class UsageAlertStateStore {
    static let userDefaultsKey = "aiquokka.usageAlert.sentStates"

    private struct StoredState: Codable {
        var resetDate: Date?
        var sentKinds: Set<UsageAlertKind>
    }

    private let userDefaults: UserDefaults
    private var states: [String: StoredState]

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        if let data = userDefaults.data(forKey: Self.userDefaultsKey),
           let decoded = try? JSONDecoder().decode([String: StoredState].self, from: data) {
            self.states = decoded
        } else {
            self.states = [:]
        }
    }

    func reconcile(_ evaluation: UsageWindowAlertEvaluation) {
        let key = baseKey(providerID: evaluation.providerID, windowLabel: evaluation.windowLabel)
        var state = states[key] ?? StoredState(resetDate: evaluation.resetDate, sentKinds: [])
        if state.resetDate != evaluation.resetDate {
            state = StoredState(resetDate: evaluation.resetDate, sentKinds: [])
        }
        state.sentKinds.formIntersection(evaluation.activeKinds)
        states[key] = state
        persist()
    }

    func hasSent(_ alert: UsageAlert) -> Bool {
        let key = baseKey(providerID: alert.providerID, windowLabel: alert.windowLabel)
        guard let state = states[key], state.resetDate == alert.resetDate else { return false }
        return state.sentKinds.contains(alert.kind)
    }

    func markSent(_ alert: UsageAlert) {
        let key = baseKey(providerID: alert.providerID, windowLabel: alert.windowLabel)
        var state = states[key] ?? StoredState(resetDate: alert.resetDate, sentKinds: [])
        if state.resetDate != alert.resetDate {
            state = StoredState(resetDate: alert.resetDate, sentKinds: [])
        }
        state.sentKinds.insert(alert.kind)
        states[key] = state
        persist()
    }

    private func baseKey(providerID: String, windowLabel: String) -> String {
        "\(providerID)\u{1F}\(windowLabel)"
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(states) else { return }
        userDefaults.set(data, forKey: Self.userDefaultsKey)
    }
}
```

`reconcile` must run before checking new alerts on every successful snapshot. It preserves sent kinds that are still active, removes kinds that have fallen below their thresholds, and resets all kinds when `resetDate` changes. It must never receive or persist the raw YAML, API key, balance value, or full snapshot.

- [ ] **Step 4: Run the state-store tests and confirm they pass**

Run:

```bash
swift test --filter UsageAlertStateStoreTests
```

Expected: all state persistence and rearming tests pass.

- [ ] **Step 5: Commit the state store**

```bash
git add Sources/AiQokkaMenubar/UsageAlertStateStore.swift Tests/AiQokkaMenubarTests/UsageAlertStateStoreTests.swift
git commit -m "feat: persist usage alert state"
```

## Task 3: Add the notification adapter and coordinator

**Files:**
- Create: `Sources/AiQokkaMenubar/UsageNotificationClient.swift`
- Create: `Sources/AiQokkaMenubar/UsageAlertCoordinator.swift`
- Test: `Tests/AiQokkaMenubarTests/UsageAlertCoordinatorTests.swift`

- [ ] **Step 1: Write failing coordinator tests with an in-memory notification client**

Define a `@MainActor` recording fake in the test file and cover explicit authorization, permission-state refresh without prompting, duplicate suppression, escalation, and retry after delivery failure:

```swift
@testable import AiQokkaMenubar
import Foundation
import XCTest

@MainActor
final class UsageAlertCoordinatorTests: XCTestCase {
    func testFirstSuccessfulSnapshotRequestsAuthorizationAndSendsAlert() async throws {
        let client = RecordingNotificationClient()
        let coordinator = makeCoordinator(client: client)
        let snapshot = snapshot(usedPercent: 80)

        await coordinator.process(snapshot: snapshot, now: Date(timeIntervalSince1970: 1_000_000))

        XCTAssertEqual(client.authorizationRequests, 1)
        XCTAssertEqual(client.sentAlerts.map(\.kind), [.nearingLimit])
        XCTAssertEqual(coordinator.highestSeverity, .warning)
    }

    func testRepeatedRefreshDoesNotSendTheSameAlertTwice() async {
        let client = RecordingNotificationClient()
        let coordinator = makeCoordinator(client: client)
        let now = Date(timeIntervalSince1970: 1_000_000)
        let snapshot = snapshot(usedPercent: 80)

        await coordinator.process(snapshot: snapshot, now: now)
        await coordinator.process(snapshot: snapshot, now: now.addingTimeInterval(60))

        XCTAssertEqual(client.sentAlerts.count, 1)
    }

    func testEscalationSendsCriticalAlertAfterWarning() async {
        let client = RecordingNotificationClient()
        let coordinator = makeCoordinator(client: client)
        let now = Date(timeIntervalSince1970: 1_000_000)

        await coordinator.process(snapshot: snapshot(usedPercent: 80), now: now)
        await coordinator.process(snapshot: snapshot(usedPercent: 95), now: now.addingTimeInterval(60))

        XCTAssertEqual(client.sentAlerts.map(\.kind), [.nearingLimit, .critical])
        XCTAssertEqual(coordinator.highestSeverity, .critical)
    }

    func testFailedDeliveryIsRetriedOnTheNextRefresh() async {
        let client = RecordingNotificationClient()
        client.deliveryResult = false
        let coordinator = makeCoordinator(client: client)
        let snapshot = snapshot(usedPercent: 80)
        let now = Date(timeIntervalSince1970: 1_000_000)

        await coordinator.process(snapshot: snapshot, now: now)
        client.deliveryResult = true
        await coordinator.process(snapshot: snapshot, now: now.addingTimeInterval(60))

        XCTAssertEqual(client.sentAlerts.count, 2)
    }

    func testAuthorizationIsRequestedOnlyOnce() async {
        let client = RecordingNotificationClient()
        let coordinator = makeCoordinator(client: client)
        let now = Date(timeIntervalSince1970: 1_000_000)

        await coordinator.process(snapshot: snapshot(usedPercent: 0), now: now)
        await coordinator.process(snapshot: snapshot(usedPercent: 0), now: now.addingTimeInterval(60))

        XCTAssertEqual(client.authorizationRequests, 1)
    }

    private func makeCoordinator(client: RecordingNotificationClient) -> UsageAlertCoordinator {
        let name = "AiQokkaUsageAlertCoordinatorTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        addTeardownBlock { defaults.removePersistentDomain(forName: name) }
        return UsageAlertCoordinator(
            stateStore: UsageAlertStateStore(userDefaults: defaults),
            notificationClient: client
        )
    }

    private func snapshot(usedPercent: Double) -> UsageSnapshot {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let window = UsageWindow(label: "Weekly", usedPercent: usedPercent, resetDate: now.addingTimeInterval(6 * 24 * 60 * 60), resetText: nil)
        let provider = ProviderUsage(id: "codex", name: "Codex", plan: "plus", error: nil, windows: [window], extras: [])
        return UsageSnapshot(providers: [provider], fetchedAt: now)
    }
}

@MainActor
private final class RecordingNotificationClient: UsageNotificationClient {
    var authorizationRequests = 0
    var sentAlerts: [UsageAlert] = []
    var deliveryResult = true

    func requestAuthorization() async {
        authorizationRequests += 1
    }

    func send(_ alert: UsageAlert) async -> Bool {
        sentAlerts.append(alert)
        return deliveryResult
    }
}
```

- [ ] **Step 2: Run coordinator tests and verify the missing protocol/coordinator fails**

Run:

```bash
swift test --filter UsageAlertCoordinatorTests
```

Expected: compilation fails because `UsageNotificationClient` and `UsageAlertCoordinator` do not exist yet.

- [ ] **Step 3: Implement the protocol, system adapter, and coordinator**

Create the main-actor protocol and production adapter in `UsageNotificationClient.swift`:

```swift
import Foundation
import UserNotifications

@MainActor
protocol UsageNotificationClient: AnyObject {
    func requestAuthorization() async
    func send(_ alert: UsageAlert) async -> Bool
}

@MainActor
final class SystemUsageNotificationClient: UsageNotificationClient {
    private let center: UNUserNotificationCenter

    init(center: UNUserNotificationCenter = .current()) {
        self.center = center
    }

    func requestAuthorization() async {
        _ = try? await center.requestAuthorization(options: [.alert, .sound])
    }

    func send(_ alert: UsageAlert) async -> Bool {
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else {
            return false
        }

        let content = UNMutableNotificationContent()
        content.title = alert.notificationTitle
        content.body = alert.notificationBody
        content.sound = .default
        let request = UNNotificationRequest(identifier: alert.id, content: content, trigger: nil)

        do {
            try await center.add(request)
            return true
        } catch {
            return false
        }
    }
}
```

Create the coordinator in `UsageAlertCoordinator.swift`:

```swift
import Combine
import Foundation

@MainActor
final class UsageAlertCoordinator: ObservableObject {
    @Published private(set) var highestSeverity: UsageAlertSeverity = .normal

    private let evaluator: UsageAlertEvaluator
    private let stateStore: UsageAlertStateStore
    private let notificationClient: any UsageNotificationClient
    private var authorizationRequested = false

    init(
        evaluator: UsageAlertEvaluator = UsageAlertEvaluator(),
        stateStore: UsageAlertStateStore = UsageAlertStateStore(),
        notificationClient: any UsageNotificationClient = SystemUsageNotificationClient()
    ) {
        self.evaluator = evaluator
        self.stateStore = stateStore
        self.notificationClient = notificationClient
    }

    func process(snapshot: UsageSnapshot, now: Date = Date()) async {
        let evaluation = evaluator.evaluate(snapshot: snapshot, now: now)
        highestSeverity = evaluation.highestSeverity

        for window in evaluation.windows {
            stateStore.reconcile(window)
        }

        if !authorizationRequested {
            authorizationRequested = true
            await notificationClient.requestAuthorization()
        }

        for alert in evaluation.alerts {
            guard !stateStore.hasSent(alert) else { continue }
            guard await notificationClient.send(alert) else { continue }
            stateStore.markSent(alert)
        }
    }
}
```

Do not mark a notification as sent when authorization is denied or `UNUserNotificationCenter.add` fails. The coordinator must continue to publish `highestSeverity` even when notification delivery is unavailable.

- [ ] **Step 4: Run coordinator tests and confirm they pass**

Run:

```bash
swift test --filter UsageAlertCoordinatorTests
```

Expected: all coordinator tests pass. If the macOS SDK does not expose an async UserNotifications overload under the selected Swift toolchain, keep the same protocol and wrap the existing completion-handler APIs with checked continuations; do not change the coordinator contract or mark state before the completion reports success.

- [ ] **Step 5: Commit the notification layer**

```bash
git add Sources/AiQokkaMenubar/UsageNotificationClient.swift Sources/AiQokkaMenubar/UsageAlertCoordinator.swift Tests/AiQokkaMenubarTests/UsageAlertCoordinatorTests.swift
git commit -m "feat: add usage alert notifications"
```

## Task 4: Trigger alerts only after successful `UsageStore` refreshes

**Files:**
- Modify: `Sources/AiQokkaMenubar/UsageStore.swift`
- Test: `Tests/AiQokkaMenubarTests/UsageStoreTests.swift`

- [ ] **Step 1: Add failing callback tests**

Add an async success-only observer test to `UsageStoreTests.swift`:

```swift
func testSuccessfulRefreshInvokesSnapshotHandler() async {
    let recorder = SnapshotRecorder()
    let snapshot = UsageSnapshot(providers: [], fetchedAt: Date(timeIntervalSince1970: 123))
    let store = UsageStore(
        loader: { snapshot },
        didLoadSnapshot: { loaded in
            await recorder.record(loaded)
        }
    )

    await store.refresh()

    let values = await recorder.values()
    XCTAssertEqual(values, [snapshot])
}

func testFailedRefreshDoesNotInvokeSnapshotHandler() async {
    let recorder = SnapshotRecorder()
    let store = UsageStore(
        loader: { throw StoreTestError.network },
        didLoadSnapshot: { loaded in
            await recorder.record(loaded)
        }
    )

    await store.refresh()

    let values = await recorder.values()
    XCTAssertEqual(values, [])
}

private actor SnapshotRecorder {
    private var snapshots: [UsageSnapshot] = []

    func record(_ snapshot: UsageSnapshot) {
        snapshots.append(snapshot)
    }

    func values() -> [UsageSnapshot] {
        snapshots
    }
}
```

- [ ] **Step 2: Run the focused store tests and verify the new initializer argument fails**

Run:

```bash
swift test --filter UsageStoreTests
```

Expected: compilation fails because `UsageStore` has no `didLoadSnapshot` callback yet.

- [ ] **Step 3: Add the callback without changing refresh/error behavior**

Add this typealias and initializer property:

```swift
typealias UsageSnapshotHandler = @MainActor (UsageSnapshot) async -> Void

@MainActor
final class UsageStore: ObservableObject {
    private let didLoadSnapshot: UsageSnapshotHandler?

    init(
        loader: @escaping UsageSnapshotLoader,
        sleep: @escaping UsageSleeper = { duration in
            try await Task.sleep(for: duration)
        },
        didLoadSnapshot: UsageSnapshotHandler? = nil
    ) {
        self.loader = loader
        self.sleep = sleep
        self.didLoadSnapshot = didLoadSnapshot
    }
}
```

After `snapshot = nextSnapshot` and `lastUpdated = nextSnapshot.fetchedAt`, invoke the handler before leaving the success branch:

```swift
if let didLoadSnapshot {
    await didLoadSnapshot(nextSnapshot)
}
```

Keep the callback out of the `catch` branch. The callback must not receive stale snapshots or failed loads, and the existing `isRefreshing`, `lastError`, and overlap guard behavior must remain unchanged.

- [ ] **Step 4: Run all store tests**

Run:

```bash
swift test --filter UsageStoreTests
```

Expected: all existing store tests plus the two callback tests pass.

- [ ] **Step 5: Commit store integration point**

```bash
git add Sources/AiQokkaMenubar/UsageStore.swift Tests/AiQokkaMenubarTests/UsageStoreTests.swift
git commit -m "feat: observe successful usage refreshes"
```

## Task 5: Wire the shared coordinator into the App and menu bar

**Files:**
- Modify: `Sources/AiQokkaMenubar/App.swift`

- [ ] **Step 1: Connect one coordinator to the existing store**

In `AiQokkaMenubarApp.init()`, create the coordinator before the store and pass an async success callback to the store:

```swift
let alertCoordinator = UsageAlertCoordinator()
let store = UsageStore(loader: {
    let yaml = try await runner.fetchYAML()
    return try decoder.decode(yaml: yaml)
}, didLoadSnapshot: { snapshot in
    await alertCoordinator.process(snapshot: snapshot)
})

_store = StateObject(wrappedValue: store)
_alertCoordinator = StateObject(wrappedValue: alertCoordinator)
```

Add `@StateObject private var alertCoordinator: UsageAlertCoordinator` alongside the existing store and display-mode state. Keep the existing standalone window controller constructed from the same `store`; do not create a second runner, decoder, store, or alert coordinator.

- [ ] **Step 2: Expose alert severity in `MenuBarSummaryView`**

Change the view initializer data from only `store` to `store` plus an observed `alertCoordinator`. Choose the symbol in this order:

```swift
if store.snapshot == nil && store.lastError != nil {
    "exclamationmark.triangle"
} else {
    alertCoordinator.highestSeverity == .critical
        ? "bell.badge.fill"
        : alertCoordinator.highestSeverity == .warning
            ? "bell.badge"
            : "gauge.with.dots.needle.67percent"
}
```

Use an orange tint for `.warning`, a red tint for `.critical`, and the existing default tint for `.normal`. Preserve the current spinner and highest-usage percentage text. Error state must continue to take precedence over alert state when there is no successful snapshot.

- [ ] **Step 3: Build the executable target**

Run:

```bash
swift build
```

Expected: exit code 0 with no Swift concurrency errors. If the `MenuBarSummaryView` initializer call is missing the new coordinator argument, fix both the call in `body` and the property declaration before proceeding.

- [ ] **Step 4: Commit App wiring**

```bash
git add Sources/AiQokkaMenubar/App.swift
git commit -m "feat: show usage alert status in menu bar"
```

## Task 6: Full verification and packaged-app acceptance

**Files:**
- No new source files; verify the files changed in Tasks 1–5.

- [ ] **Step 1: Run the complete Swift test suite**

Run:

```bash
swift test
```

Expected: every existing and new XCTest passes, including YAML, proxy, store, display-mode, evaluator, state-store, and coordinator tests. Record the exact test count from the command output.

- [ ] **Step 2: Run static diff checks**

Run:

```bash
git diff --check
git diff --check main...HEAD
git status --short
```

Expected: no whitespace errors and no unexpected tracked files. Preserve the pre-existing untracked `.DS_Store` and `docs/research/` without staging or deleting them.

- [ ] **Step 3: Build the distributable app bundle**

Run:

```bash
CONFIGURATION=release ./scripts/build-app.sh
plutil -p dist/aiquokka.app/Contents/Info.plist
file dist/aiquokka.app/Contents/MacOS/AiQokkaMenubar
```

Expected: the script exits 0, the bundle exists at `dist/aiquokka.app`, `LSUIElement` remains true, and the executable is a macOS arm64 binary. The build script may replace only the exact `dist/aiquokka.app` output bundle.

- [ ] **Step 4: Perform real macOS notification checks**

With a local `aiquokka --yml` fixture or a real configured provider, verify each item manually:

1. Launch the app, open the menu bar detail or standalone window, click “开启”, and confirm macOS asks for notification permission from that visible user action.
2. At a fixed 80% window, confirm one warning notification and an orange menu bar bell; refresh repeatedly and confirm no duplicate warning.
3. Move the same window to 95%, confirm one critical notification and a red menu bar bell.
4. Restart the app while the same reset window remains at 95%; confirm no duplicate critical notification because state persisted.
5. Feed a new reset timestamp or a usage value below the threshold; confirm the corresponding alert can fire again when the threshold is crossed later.
6. Deny notifications in System Settings; confirm the menu bar severity still updates and a later delivery attempt is not marked sent prematurely.
7. Trigger a provider/network error; confirm no new notification and the last successful snapshot behavior remains unchanged.
8. Switch between menu bar and standalone-window display modes; confirm both surfaces continue sharing the same data and alert coordinator.

- [ ] **Step 5: Record completion evidence**

Before claiming completion, report the fresh `swift test` result, build result, bundle path, and which manual notification checks were actually performed. If notification permission, a suitable provider state, or a real second display is unavailable, state that gate explicitly instead of treating the build as end-to-end acceptance.
