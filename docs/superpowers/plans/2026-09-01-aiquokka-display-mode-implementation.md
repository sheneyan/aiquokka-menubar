# aiquokka Display Mode Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a persisted Menu Bar / Standalone Window display mode while keeping one shared local-aiquokka data store and a permanently available menu bar entry.

**Architecture:** Add a main-actor `DisplayModeSettings` object backed by isolated `UserDefaults` storage. Keep `MenuBarExtra` as the always-available control surface and add an AppKit `StandaloneWindowController` that hosts the same SwiftUI usage view, restores its frame with an autosave name, and synchronizes close and mode-change behavior through the settings object.

**Tech Stack:** Swift 6, SwiftUI, AppKit, Combine `ObservableObject`, XCTest, Swift Package Manager, macOS 13+.

---

### Task 1: Add the persisted display-mode model

**Files:**
- Create: `Sources/AiQokkaMenubar/DisplayMode.swift`
- Create: `Tests/AiQokkaMenubarTests/DisplayModeTests.swift`

- [ ] **Step 1: Write failing persistence tests**

Create an isolated `UserDefaults` suite for every test and cover the default, round trip, and unknown-value behavior:

```swift
@testable import AiQokkaMenubar
import XCTest

@MainActor
final class DisplayModeSettingsTests: XCTestCase {
    func testDefaultsToMenuBarWhenNoPreferenceExists() {
        let defaults = makeDefaults()
        let settings = DisplayModeSettings(userDefaults: defaults)

        XCTAssertEqual(settings.mode, .menuBar)
    }

    func testPersistsStandaloneWindowForTheNextInstance() {
        let defaults = makeDefaults()
        let first = DisplayModeSettings(userDefaults: defaults)

        first.mode = .standaloneWindow

        let second = DisplayModeSettings(userDefaults: defaults)
        XCTAssertEqual(second.mode, .standaloneWindow)
        XCTAssertEqual(defaults.string(forKey: DisplayModeSettings.userDefaultsKey), "standaloneWindow")
    }

    func testUnknownStoredValueFallsBackToMenuBar() {
        let defaults = makeDefaults()
        defaults.set("future-mode", forKey: DisplayModeSettings.userDefaultsKey)

        let settings = DisplayModeSettings(userDefaults: defaults)

        XCTAssertEqual(settings.mode, .menuBar)
    }

    private func makeDefaults() -> UserDefaults {
        let suiteName = "AiQokkaDisplayModeTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        addTeardownBlock {
            defaults.removePersistentDomain(forName: suiteName)
        }
        return defaults
    }
}
```

- [ ] **Step 2: Run the focused test to verify the missing model fails**

Run:

```bash
swift test --filter DisplayModeSettingsTests
```

Expected: compilation fails because `DisplayModeSettings` and `DisplayMode` do not exist yet.

- [ ] **Step 3: Implement the minimal model**

Create the two supported modes and a main-actor observable settings object. `mode` writes only the selected raw value; initialization reads an unknown or missing value as `.menuBar`.

```swift
import Combine
import Foundation

enum DisplayMode: String, CaseIterable, Identifiable, Sendable {
    case menuBar
    case standaloneWindow

    var id: String { rawValue }

    var title: String {
        switch self {
        case .menuBar: return "菜单栏"
        case .standaloneWindow: return "独立窗口"
        }
    }
}

@MainActor
final class DisplayModeSettings: ObservableObject {
    static let userDefaultsKey = "aiquokka.displayMode"

    @Published var mode: DisplayMode {
        didSet {
            userDefaults.set(mode.rawValue, forKey: Self.userDefaultsKey)
        }
    }

    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        self.mode = DisplayMode(
            rawValue: userDefaults.string(forKey: Self.userDefaultsKey) ?? ""
        ) ?? .menuBar
    }
}
```

- [ ] **Step 4: Run the focused test to verify persistence**

Run:

```bash
swift test --filter DisplayModeSettingsTests
```

Expected: all three tests pass.

- [ ] **Step 5: Commit the model and tests**

```bash
git add Sources/AiQokkaMenubar/DisplayMode.swift Tests/AiQokkaMenubarTests/DisplayModeTests.swift
git commit -m "feat: persist aiquokka display mode"
```

### Task 2: Add the standalone window controller implementation

**Files:**
- Create: `Sources/AiQokkaMenubar/StandaloneWindowController.swift`

- [ ] **Step 1: Define the controller behavior before integration**

The controller must own at most one window, host the existing usage view through `NSHostingController`, restore the frame using a fixed autosave name, and activate the app when showing. It receives the shared `UsageStore` and `DisplayModeSettings`; it must not create another loader or refresh task.

Use these constants and state transitions:

```swift
@MainActor
final class StandaloneWindowController: NSObject, NSWindowDelegate {
    static let windowIdentifier = NSUserInterfaceItemIdentifier("com.local.aiquokka.standalone-window")
    static let frameAutosaveName = NSWindow.FrameAutosaveName("AiQokkaStandaloneWindow")

    private let store: UsageStore
    private let displayMode: DisplayModeSettings
    private var closingForModeChange = false
    private var terminating = false
    private(set) var window: NSWindow?

    init(store: UsageStore, displayMode: DisplayModeSettings) {
        self.store = store
        self.displayMode = displayMode
        super.init()
    }
}
```

- [ ] **Step 2: Implement show, close, and frame restoration**

Create a titled, closable, miniaturizable, resizable `NSWindow` with a 380pt initial content width. Set `NSHostingController.sizingOptions = [.intrinsicContentSize]`, assign the hosted `UsagePopoverView` with the standalone surface, set `setFrameAutosaveName`, then call `setFrameUsingName` and center only when no saved frame exists.

The controller's public methods must follow this shape:

```swift
func show() {
    if let window {
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        return
    }

    let hostedView = UsagePopoverView(
        store: store,
        displayMode: displayMode,
        surface: .standaloneWindow,
        onDisplayModeChanged: { [weak self] mode in
            if mode == .standaloneWindow {
                self?.show()
            } else {
                self?.close()
            }
        }
    )
    let hostingController = NSHostingController(rootView: hostedView)
    hostingController.sizingOptions = [.intrinsicContentSize]

    let fittingHeight = max(hostingController.view.fittingSize.height, 200)
    let newWindow = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 380, height: fittingHeight),
        styleMask: [.titled, .closable, .miniaturizable, .resizable],
        backing: .buffered,
        defer: false
    )
    newWindow.title = "aiquokka"
    newWindow.identifier = Self.windowIdentifier
    newWindow.isReleasedWhenClosed = false
    newWindow.delegate = self
    newWindow.contentViewController = hostingController
    newWindow.setFrameAutosaveName(Self.frameAutosaveName)
    if !newWindow.setFrameUsingName(Self.frameAutosaveName) {
        newWindow.center()
    }

    window = newWindow
    newWindow.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
}

func close() {
    guard let window else { return }
    closingForModeChange = true
    window.close()
    closingForModeChange = false
}
```

- [ ] **Step 3: Implement close synchronization and termination protection**

Register for `NSApplication.willTerminateNotification` and set `terminating = true` before the window closes during app termination. In `windowWillClose`, clear the owned window; only when the close is user initiated, the app is not terminating, and the setting is still `.standaloneWindow`, set `displayMode.mode = .menuBar`. This keeps a manually closed window recoverable through the menu bar without changing the saved mode during a normal quit.

```swift
func windowWillClose(_ notification: Notification) {
    window = nil
    guard !closingForModeChange,
          !terminating,
          displayMode.mode == .standaloneWindow
    else { return }

    displayMode.mode = .menuBar
}
```

- [ ] **Step 4: Defer the compile checkpoint until the shared view API is added**

The controller's `show()` method intentionally calls the `UsagePopoverView` initializer introduced in Task 3, so the controller and view API must be compiled together. Do not run a test command at this intermediate boundary; commit the controller and use Task 3 Step 3 as the first compile checkpoint after both files have their final signatures.

- [ ] **Step 5: Commit the window controller**

```bash
git add Sources/AiQokkaMenubar/StandaloneWindowController.swift
git commit -m "feat: add standalone usage window controller"
```

### Task 3: Complete the shared usage view and wire the standalone controller

**Files:**
- Modify: `Sources/AiQokkaMenubar/UsagePopoverView.swift`
- Modify: `Sources/AiQokkaMenubar/App.swift`

- [ ] **Step 1: Add a surface parameter and display-mode picker to the usage view**

Add a small internal surface enum and make the view receive the shared settings plus a mode-change closure:

```swift
enum UsageSurface {
    case menuBar
    case standaloneWindow
}

struct UsagePopoverView: View {
    @ObservedObject var store: UsageStore
    @ObservedObject var displayMode: DisplayModeSettings
    let surface: UsageSurface
    let onDisplayModeChanged: (DisplayMode) -> Void
}
```

Insert a labeled segmented picker between the provider content and the existing footer. Its binding must write `displayMode.mode` and immediately call `onDisplayModeChanged`:

```swift
private var displayModePicker: some View {
    VStack(alignment: .leading, spacing: 6) {
        Text("显示方式")
            .font(.caption)
            .foregroundStyle(.secondary)
        Picker("显示方式", selection: Binding(
            get: { displayMode.mode },
            set: { newMode in
                displayMode.mode = newMode
                onDisplayModeChanged(newMode)
            }
        )) {
            ForEach(DisplayMode.allCases) { mode in
                Text(mode.title).tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 10)
}
```

Keep the existing 380pt width, content-driven vertical sizing, and 560pt scroll limit for both surfaces. The standalone surface may use the standard window's resizable frame, but it must not reintroduce a fixed 520pt height.

- [ ] **Step 2: Integrate shared settings and controller into the App**

Keep the `DisplayModeSettings` created in Task 1 Step 3 and retain the `StandaloneWindowController` created in Task 2 beside the existing shared `UsageStore`. Keep `MenuBarExtra` unconditionally declared so the status item remains available in both modes. Pass `.menuBar` to its usage view and route mode changes to `controller.show()` or `controller.close()`.

After the store starts its existing auto-refresh, schedule `controller.show()` on the next main-queue turn when the persisted mode is `.standaloneWindow`; this avoids trying to present a window before the application has finished launching.

The relevant scene wiring must remain equivalent to:

```swift
let controller = standaloneWindowController

MenuBarExtra {
    UsagePopoverView(
        store: store,
        displayMode: displayMode,
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
    MenuBarSummaryView(store: store)
}
.menuBarExtraStyle(.window)
```

- [ ] **Step 3: Compile and run focused tests**

Run:

```bash
swift test --filter DisplayModeSettingsTests
```

Expected: all display-mode persistence tests pass and the target compiles with both SwiftUI surfaces.

- [ ] **Step 4: Commit shared-surface integration**

```bash
git add Sources/AiQokkaMenubar/App.swift Sources/AiQokkaMenubar/UsagePopoverView.swift
git commit -m "feat: switch aiquokka between menu bar and window"
```

### Task 4: Verify persistence, window lifecycle, and packaging

**Files:**
- Modify: `docs/superpowers/plans/2026-09-01-aiquokka-display-mode-implementation.md`

- [ ] **Step 1: Run the complete automated suite and packaging script**

Run:

```bash
swift test
./scripts/build-app.sh
```

Expected: all tests pass, including the existing local CLI/YAML/proxy/refresh tests, and the script produces `dist/aiquokka.app` with the existing `LSUIElement=true` configuration.

- [ ] **Step 2: Launch the packaged app and verify the menu bar surface**

Open `dist/aiquokka.app`, click the `aiquokka` status item, and confirm the popover contains:

1. the current Codex and Grok usage data;
2. a `显示方式` segmented picker with `菜单栏` selected;
3. the existing refresh and quit controls.

- [ ] **Step 3: Verify switching to the standalone window**

Select `独立窗口` in the popover and confirm:

1. a titled `aiquokka` window appears immediately;
2. the window displays the same timestamp and provider data without triggering a second refresh task;
3. the window can be dragged to another display;
4. the menu bar status item remains visible and can still open the popover.

- [ ] **Step 4: Verify both recovery paths and position restoration**

Test these exact transitions:

1. choose `菜单栏` inside the standalone window; the window closes and the menu bar popover remains available;
2. choose `独立窗口` again; the same window behavior returns;
3. close the standalone window with its close button; the mode returns to `菜单栏` and can be reopened from the menu bar;
4. choose `独立窗口`, move the window, quit the App, and relaunch it; the window reopens at the saved position;
5. click `退出` while standalone mode is selected, relaunch, and confirm the saved mode remains `独立窗口`.

- [ ] **Step 5: Check the final diff and commit verification notes**

Run:

```bash
git diff --check
git status --short
git log --oneline --decorate -6
```

Record the final test count and packaged artifact path in the handoff. Do not add credentials, provider output, or generated build directories to Git.
