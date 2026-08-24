# aiquokka macOS Menubar Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a native macOS menu bar app that runs the locally installed `aiquokka --yml`, summarizes usage in the menu bar, and shows complete provider data in a clickable popover.

**Architecture:** A Swift Package executable target hosts a SwiftUI `MenuBarExtra` app. `UsageStore` owns refresh state and a 60-second timer; `UsageCommandRunner` locates and runs `aiquokka` without reading credentials; `UsageYAMLDecoder` maps Yams output into app-owned models. A small bundle script turns the executable into a launchable `.app` for local validation.

**Tech Stack:** Swift 5.9+, SwiftUI, Foundation `Process`, Swift Concurrency, Swift Package Manager, Yams, XCTest, macOS 13+.

---

## File map

- Create: `Package.swift` — executable target, test target, Yams dependency, macOS deployment target.
- Create: `Sources/AiQokkaMenubar/App.swift` — app entry point and `MenuBarExtra` scene.
- Create: `Sources/AiQokkaMenubar/UsageModels.swift` — decoded and display-facing value types.
- Create: `Sources/AiQokkaMenubar/UsageYAMLDecoder.swift` — YAML-to-model conversion and tolerant date handling.
- Create: `Sources/AiQokkaMenubar/UsageCommandRunner.swift` — executable discovery, subprocess execution, timeout, and typed errors.
- Create: `Sources/AiQokkaMenubar/UsageStore.swift` — observable snapshot, refresh lifecycle, timer, and summary calculation.
- Create: `Sources/AiQokkaMenubar/UsagePopoverView.swift` — popover layout, provider cards, refresh and quit actions.
- Create: `Sources/AiQokkaMenubar/Resources/Info.plist` — agent-only bundle metadata and accessory activation policy.
- Create: `scripts/build-app.sh` — build arm64 app bundle from the SwiftPM executable.
- Create: `Tests/AiQokkaMenubarTests/UsageYAMLDecoderTests.swift` — parser fixtures and tolerant-field tests.
- Create: `Tests/AiQokkaMenubarTests/UsageCommandRunnerTests.swift` — injected process/path behavior tests.
- Create: `Tests/AiQokkaMenubarTests/UsageStoreTests.swift` — refresh state and duplicate-refresh tests.
- Create: `Tests/AiQokkaMenubarTests/Fixtures/aggregate.yml` — sanitized multi-provider fixture.
- Create: `Tests/AiQokkaMenubarTests/Fixtures/partial.yml` — missing optional fields and unknown fields fixture.
- Create: `Tests/AiQokkaMenubarTests/Fixtures/invalid.yml` — malformed YAML fixture.

### Task 1: Create the SwiftPM project and executable shell

**Files:**
- Create: `Package.swift`
- Create: `Sources/AiQokkaMenubar/App.swift`
- Create: `Sources/AiQokkaMenubar/Resources/Info.plist`
- Create: `Tests/AiQokkaMenubarTests/UsageYAMLDecoderTests.swift`

- [ ] **Step 1: Add the package manifest**

Declare an executable product named `AiQokkaMenubar`, a test target, Yams from `https://github.com/jpsim/Yams.git` using the `4.0.0 ..< 6.0.0` range, and `.macOS(.v13)` as the minimum platform.

- [ ] **Step 2: Add the minimal app entry point**

Create an `@main` SwiftUI `App` with a `MenuBarExtra("aiquokka", systemImage: "gauge.with.dots.needle.67percent")` scene and a placeholder `Text("Loading…")` label. Use `.menuBarExtraStyle(.window)` so the final popover can scroll and retain a fixed width.

- [ ] **Step 3: Add bundle metadata**

Set `LSUIElement` to `true`, `CFBundleIdentifier` to `com.local.aiquokka-menubar`, and `CFBundleName` to `aiquokka` in `Sources/AiQokkaMenubar/Resources/Info.plist`.

- [ ] **Step 4: Add a first test target and compile check**

Add an empty XCTest case so SwiftPM resolves both targets, then run:

```bash
swift test
```

Expected: the package resolves, compiles, and exits 0 with at least one passing test.

- [ ] **Step 5: Commit**

```bash
git add Package.swift Sources Tests
git commit -m "chore: scaffold aiquokka menubar app"
```

### Task 2: Define models and YAML decoding with tests first

**Files:**
- Create: `Sources/AiQokkaMenubar/UsageModels.swift`
- Create: `Sources/AiQokkaMenubar/UsageYAMLDecoder.swift`
- Create: `Tests/AiQokkaMenubarTests/Fixtures/aggregate.yml`
- Create: `Tests/AiQokkaMenubarTests/Fixtures/partial.yml`
- Create: `Tests/AiQokkaMenubarTests/Fixtures/invalid.yml`
- Modify: `Tests/AiQokkaMenubarTests/UsageYAMLDecoderTests.swift`

- [ ] **Step 1: Write failing parser tests**

Cover these exact assertions: aggregate YAML returns providers keyed in sorted display order; `used_percent` is decoded as `Double`; `resets_at` is preserved as an absolute `Date` when ISO-8601 parses; `extra.value` accepts both quoted and unquoted scalars; absent `plan`, `windows`, and `extra` become empty/nil; unknown top-level keys are ignored; malformed YAML throws a typed decode error; an invalid date preserves its original string instead of failing the full document.

- [ ] **Step 2: Run the parser tests and verify they fail**

```bash
swift test --filter UsageYAMLDecoderTests
```

Expected: compile or test failure because the model and decoder do not exist yet.

- [ ] **Step 3: Implement the app-owned models**

Define `UsageSnapshot(providers: [ProviderUsage], fetchedAt: Date)`, `ProviderUsage(id: String, name: String, plan: String?, windows: [UsageWindow], extras: [UsageExtra])`, `UsageWindow(label: String, usedPercent: Double?, resetDate: Date?, resetText: String?)`, and `UsageExtra(label: String, value: String)`. Add computed properties for highest usage and a stable provider display sort.

- [ ] **Step 4: Implement tolerant Yams conversion**

Use `Yams.load(yaml:)` and convert `Node`/dictionary values explicitly. Accept numeric scalars and numeric strings for `used_percent`; format unknown scalar values with `String(describing:)`; parse dates with ISO-8601 fractional and non-fractional formatters; preserve unparseable reset text. Throw `UsageDecodeError.invalidDocument` only when the root or provider shape cannot be interpreted.

- [ ] **Step 5: Run the parser tests and verify they pass**

```bash
swift test --filter UsageYAMLDecoderTests
```

Expected: all parser tests pass.

- [ ] **Step 6: Commit**

```bash
git add Sources/AiQokkaMenubar/UsageModels.swift Sources/AiQokkaMenubar/UsageYAMLDecoder.swift Tests
git commit -m "feat: decode aiquokka yaml into usage models"
```

### Task 3: Implement command discovery and subprocess execution

**Files:**
- Create: `Sources/AiQokkaMenubar/UsageCommandRunner.swift`
- Create: `Tests/AiQokkaMenubarTests/UsageCommandRunnerTests.swift`

- [ ] **Step 1: Write failing runner tests**

Inject a `CommandExecutor` protocol and fake executor. Test that explicit candidate paths are tried in order, the first executable path wins, stdout is returned on exit 0, stderr and exit code become a typed non-zero error, and a timeout becomes a typed timeout error. Ensure runner arguments are exactly `--yml` and no shell interpolation is used.

- [ ] **Step 2: Run the runner tests and verify they fail**

```bash
swift test --filter UsageCommandRunnerTests
```

Expected: failure because the runner protocol and implementation are absent.

- [ ] **Step 3: Implement path discovery**

Search `/opt/homebrew/bin/aiquokka`, `/usr/local/bin/aiquokka`, `FileManager.default.homeDirectoryForCurrentUser.appending(path: "go/bin/aiquokka")`, then split the current process PATH. Deduplicate paths and return the attempted paths in the not-found error.

- [ ] **Step 4: Implement safe `Process` execution**

Launch the resolved executable directly with `arguments = ["--yml"]`, separate pipes for stdout/stderr, a 30-second timeout, and termination on timeout. Decode stdout as UTF-8. Never read credential files or invoke a shell command string.

- [ ] **Step 5: Run the runner tests and verify they pass**

```bash
swift test --filter UsageCommandRunnerTests
```

Expected: all runner tests pass.

- [ ] **Step 6: Commit**

```bash
git add Sources/AiQokkaMenubar/UsageCommandRunner.swift Tests/AiQokkaMenubarTests/UsageCommandRunnerTests.swift
git commit -m "feat: run local aiquokka safely"
```

### Task 4: Add refresh state and timer behavior

**Files:**
- Create: `Sources/AiQokkaMenubar/UsageStore.swift`
- Modify: `Tests/AiQokkaMenubarTests/UsageStoreTests.swift`

- [ ] **Step 1: Write failing store tests**

Use injected clock/runner dependencies to test: initialization starts in idle/no-data; `refresh()` enters loading; success stores snapshot and fetched time; failure with an old snapshot keeps old data and exposes error; failure without data exposes empty error state; a second refresh while loading does not invoke the runner twice; scheduled refresh interval is exactly 60 seconds.

- [ ] **Step 2: Run the store tests and verify they fail**

```bash
swift test --filter UsageStoreTests
```

Expected: failure because `UsageStore` is absent.

- [ ] **Step 3: Implement `@MainActor @Observable` store**

Use `@MainActor` and the Observation framework. Expose `snapshot`, `isRefreshing`, `lastUpdated`, and `lastError`; inject an async runner and a timer sequence. Preserve the last good snapshot on later failures and suppress overlapping refreshes.

- [ ] **Step 4: Implement the 60-second lifecycle**

Start one immediate refresh from the App task, then run an async loop with `try await Task.sleep(for: .seconds(60))`. Cancel the loop on store deinitialization. Manual refresh calls the same guarded method.

- [ ] **Step 5: Run the store tests and verify they pass**

```bash
swift test --filter UsageStoreTests
```

Expected: all store tests pass without waiting a real 60 seconds by using the injected timer.

- [ ] **Step 6: Commit**

```bash
git add Sources/AiQokkaMenubar/UsageStore.swift Tests/AiQokkaMenubarTests/UsageStoreTests.swift
git commit -m "feat: add usage refresh store"
```

### Task 5: Build the native menu bar and detail popover

**Files:**
- Modify: `Sources/AiQokkaMenubar/App.swift`
- Create: `Sources/AiQokkaMenubar/UsagePopoverView.swift`

- [ ] **Step 1: Implement menu bar summary**

Create the store once at App scope. Show a `Q`/gauge icon, a compact highest-usage percentage when data exists, a progress indicator while refreshing, and `exclamationmark.triangle` when no data/error exists. Clicking opens the popover.

- [ ] **Step 2: Implement the popover header**

Use a fixed frame around 380×520, a title, last-updated text, refresh button with `ProgressView` while loading, and an error banner that distinguishes stale data from no data. Add a bottom `Quit` button calling `NSApplication.shared.terminate(nil)`.

- [ ] **Step 3: Implement provider cards**

Render a `ScrollView` with one disclosure section per provider. Each collapsed row shows provider name, plan, highest usage bar, percentage, and reset summary. Expanded content lists every window and every extra key/value pair. Use `.monospacedDigit()` for percentages and reset countdowns.

- [ ] **Step 4: Implement date and reset presentation**

Show relative reset time using `RelativeDateTimeFormatter`; show the original reset text when parsing failed; include an absolute date in a secondary line using the system locale/time zone.

- [ ] **Step 5: Run build and UI compile verification**

```bash
swift test
swift build
```

Expected: all tests pass and the executable builds without warnings that indicate unavailable macOS APIs.

- [ ] **Step 6: Commit**

```bash
git add Sources/AiQokkaMenubar/App.swift Sources/AiQokkaMenubar/UsagePopoverView.swift
git commit -m "feat: add menubar usage popover"
```

### Task 6: Package a launchable local `.app`

**Files:**
- Create: `scripts/build-app.sh`

- [ ] **Step 1: Write the bundle script**

The script must use `set -euo pipefail`, build `swift build -c release`, create `dist/aiquokka.app/Contents/MacOS` and `Contents/Resources`, copy the executable and `Info.plist`, and write `CFBundleExecutable`, `CFBundlePackageType=APPL`, and `CFBundleVersion` metadata. It must not copy credentials or generated YAML into the bundle.

- [ ] **Step 2: Run the bundle script**

```bash
./scripts/build-app.sh
```

Expected: `dist/aiquokka.app` exists and contains an executable plus `Contents/Info.plist`.

- [ ] **Step 3: Verify the bundle and run the real local command path**

```bash
plutil -p dist/aiquokka.app/Contents/Info.plist
dist/aiquokka.app/Contents/MacOS/AiQokkaMenubar
/Users/sheneyan/go/bin/aiquokka --yml
```

Expected: plist reports an accessory app, the executable starts without opening a Dock window, and the real command emits YAML without the app needing direct credential access.

- [ ] **Step 4: Add the build script to the repository and commit**

```bash
git add scripts/build-app.sh
git commit -m "build: package aiquokka menubar app"
```

### Task 7: Full verification and handoff

**Files:**
- Modify: none unless verification finds a defect.

- [ ] **Step 1: Run the complete automated suite**

```bash
swift test
```

Expected: all parser, runner, and store tests pass.

- [ ] **Step 2: Build the release bundle**

```bash
./scripts/build-app.sh
```

Expected: exit 0 and a fresh `dist/aiquokka.app`.

- [ ] **Step 3: Perform focused manual acceptance**

Launch the bundle with `open dist/aiquokka.app`, confirm the menu bar item appears, click it, confirm all sanitized fixture fields are represented in the UI when using the test runner configuration, trigger “立即刷新”, and confirm the loading state clears. Then verify a missing-command error shows a retry action and does not crash the app.

- [ ] **Step 4: Check repository hygiene**

```bash
git status --short
rg -n 'credentials|auth.json|\.claude|\.codex' Sources Tests scripts || true
```

Expected: only intended source/test/build files are present; no real credential paths or captured sensitive output are committed.

- [ ] **Step 5: Commit any final verification-only fixes**

```bash
git add Package.swift Sources Tests scripts
git commit -m "test: verify aiquokka menubar app"
```

