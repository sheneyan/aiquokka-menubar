# aiquokka-menubar Public Repository Baseline Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn the current local macOS menu-bar project into a documented, licensed, privacy-reviewed public repository and publish its verified `main` branch to `sheneyan/aiquokka-menubar`.

**Architecture:** Keep the existing SwiftPM application and complete Git history. Remove machine-specific defaults, assign the stable public bundle identity, add public-facing documentation and license notices, retain only durable design documents, then gate the first push on source/history scans plus fresh test, build, and signing evidence.

**Tech Stack:** Swift 6, SwiftUI/AppKit, Swift Package Manager, XCTest, zsh, Git, GitHub CLI, macOS `plutil` and `codesign`.

---

## File map

- Modify `.gitignore` — ignore Finder metadata without hiding local research notes.
- Modify `Sources/AiQokkaMenubar/Resources/Info.plist` — replace the local placeholder bundle ID with the stable public ID.
- Modify `Sources/AiQokkaMenubar/UsageNtfy.swift` — remove the author-machine `agent-notify` fallback.
- Modify `Tests/AiQokkaMenubarTests/UsageNtfySettingsTests.swift` — lock the portable ntfy fallback behavior.
- Create `README.md` — public positioning, features, requirements, build/install instructions, privacy boundary, and limitations.
- Create `LICENSE` — MIT license for project-authored code and documentation.
- Create `THIRD_PARTY_NOTICES.md` — bundled Yams 4.0.6 MIT notice and external-runtime clarification.
- Move `docs/superpowers/specs/*.md` to `docs/design/*.md` — retain durable product/design decisions under a public path.
- Delete `docs/superpowers/plans/*.md` — remove execution checklists from the public tree, including this plan after all earlier tasks are complete.
- Preserve untracked `docs/research/` — never add, delete, or rewrite these local notes.

### Task 1: Remove machine-specific defaults and establish the public app identity

**Files:**
- Modify: `.gitignore`
- Modify: `Sources/AiQokkaMenubar/Resources/Info.plist`
- Modify: `Sources/AiQokkaMenubar/UsageNtfy.swift:131-149`
- Modify: `Tests/AiQokkaMenubarTests/UsageNtfySettingsTests.swift`

- [ ] **Step 1: Add a failing portability test for the ntfy executable fallback**

Insert this test before `makeDefaults()` in `UsageNtfySettingsTests`:

```swift
func testDefaultExecutablePathFallsBackToUserLocalBin() {
    let homeDirectory = FileManager.default.temporaryDirectory
        .appendingPathComponent("aiquokka-home-\(UUID().uuidString)")

    let path = UsageNtfySettings.defaultExecutablePath(
        homeDirectory: homeDirectory,
        isExecutable: { _ in false }
    )

    XCTAssertEqual(
        path,
        homeDirectory.appendingPathComponent(".local/bin/agent-notify").path
    )
}
```

- [ ] **Step 2: Run the focused test and verify the old private fallback fails it**

Run:

```bash
swift test --filter UsageNtfySettingsTests/testDefaultExecutablePathFallsBackToUserLocalBin
```

Expected: FAIL to compile because the deterministic `isExecutable` test seam does not exist yet.

- [ ] **Step 3: Replace the private fallback with the first portable candidate**

Change `defaultExecutablePath` to keep the existing `FileManager` entry point, add a deterministic test seam, and return the conventional user-local path when none exists:

```swift
static func defaultExecutablePath(
    homeDirectory: URL,
    fileManager: FileManager = .default
) -> String {
    defaultExecutablePath(
        homeDirectory: homeDirectory,
        isExecutable: { fileManager.isExecutableFile(atPath: $0) }
    )
}

static func defaultExecutablePath(
    homeDirectory: URL,
    isExecutable: (String) -> Bool
) -> String {
    let candidates = [
        homeDirectory.appendingPathComponent(".local/bin/agent-notify"),
        URL(fileURLWithPath: "/opt/homebrew/bin/agent-notify"),
        URL(fileURLWithPath: "/usr/local/bin/agent-notify")
    ]
    return candidates.first(where: { isExecutable($0.path) })?.path
        ?? candidates[0].path
}
```

- [ ] **Step 4: Run the ntfy settings tests**

Run:

```bash
swift test --filter UsageNtfySettingsTests
```

Expected: all `UsageNtfySettingsTests` pass.

- [ ] **Step 5: Set public repository hygiene and bundle identity**

Append this exact rule to `.gitignore`:

```gitignore
.DS_Store
```

Change `CFBundleIdentifier` in `Sources/AiQokkaMenubar/Resources/Info.plist` to:

```xml
<string>io.github.sheneyan.aiquokka-menubar</string>
```

- [ ] **Step 6: Verify identity, ignored metadata, and removal of the private source path**

Run:

```bash
test "$(plutil -extract CFBundleIdentifier raw Sources/AiQokkaMenubar/Resources/Info.plist)" = "io.github.sheneyan.aiquokka-menubar"
git check-ignore .DS_Store
! rg -n 'Documents/Work|/Users/' Sources Tests .gitignore Package.swift Package.resolved scripts
```

Expected: all commands exit 0; `git check-ignore` prints `.DS_Store`; the final scan prints nothing.

- [ ] **Step 7: Commit the public identity and portability cleanup**

```bash
git add .gitignore Sources/AiQokkaMenubar/Resources/Info.plist Sources/AiQokkaMenubar/UsageNtfy.swift Tests/AiQokkaMenubarTests/UsageNtfySettingsTests.swift
git commit -m "chore: prepare public app identity"
```

### Task 2: Add the project license and third-party notice

**Files:**
- Create: `LICENSE`
- Create: `THIRD_PARTY_NOTICES.md`

- [ ] **Step 1: Create the project MIT license**

Create `LICENSE` with this exact text:

```text
MIT License

Copyright (c) 2026 Yiyan Shen

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

- [ ] **Step 2: Create the Yams notice and external dependency clarification**

Create `THIRD_PARTY_NOTICES.md`:

```markdown
# Third-Party Notices

## Yams

This project links [Yams 4.0.6](https://github.com/jpsim/Yams/tree/4.0.6),
resolved at revision `9ff1cc9327586db4e0c8f46f064b6a82ec1566fa`.

The MIT License (MIT)

Copyright (c) 2016 JP Simard.

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

## aiquokka

[aiquokka](https://github.com/McKean/aiquokka) is an external runtime
dependency. This repository does not vendor or distribute its source code or
binary. aiquokka is licensed separately under the MIT License by its upstream
authors.
```

- [ ] **Step 3: Verify notices against pinned and upstream primary sources**

Run:

```bash
rg -n '9ff1cc9327586db4e0c8f46f064b6a82ec1566fa|"version" : "4.0.6"' Package.resolved THIRD_PARTY_NOTICES.md
curl -fsSL https://raw.githubusercontent.com/jpsim/Yams/4.0.6/LICENSE | diff -u - <(sed -n '/^The MIT License (MIT)$/,/^SOFTWARE\.$/p' THIRD_PARTY_NOTICES.md)
```

Expected: the pinned version and revision appear in both sources, and `diff` exits 0. If upstream license text or the pin differs, update `THIRD_PARTY_NOTICES.md` to match the pinned Yams release before proceeding.

- [ ] **Step 4: Commit licensing files**

```bash
git add LICENSE THIRD_PARTY_NOTICES.md
git commit -m "docs: add MIT and third-party licenses"
```

### Task 3: Write the public README from currently shipped behavior

**Files:**
- Create: `README.md`

- [ ] **Step 1: Create the README**

Create `README.md` with this content:

````markdown
# aiquokka-menubar

A native macOS menu bar companion for [aiquokka](https://github.com/McKean/aiquokka).

aiquokka-menubar runs the `aiquokka --yml` command installed on your Mac and presents its percentage-based usage windows in a compact menu bar interface. It is an independent, unofficial companion project and is not affiliated with the upstream aiquokka maintainers or provider vendors.

## Features

- Highest current usage shown directly in the menu bar.
- Full provider, plan, usage-window, reset-time, and extra-field details.
- Menu bar popover or standalone-window display mode.
- Automatic refresh every 60 seconds and manual refresh on demand.
- A visible red failure state while preserving the last successful snapshot.
- Native macOS notifications for fast usage, 80% usage, and 95% usage.
- Optional ntfy milestone notifications through a separately installed `agent-notify` command.
- System proxy forwarding when the local CLI needs proxy access.

## Requirements

- macOS 13 Ventura or later.
- A locally installed and configured [aiquokka](https://github.com/McKean/aiquokka).
- Swift 6 when building from source.

Install the upstream CLI and verify it independently first:

```bash
go install github.com/McKean/aiquokka@latest
aiquokka --yml
```

The App looks for `aiquokka` in this order:

1. `/opt/homebrew/bin/aiquokka`
2. `/usr/local/bin/aiquokka`
3. `~/go/bin/aiquokka`
4. Directories in the App process's `PATH`

A macOS GUI App does not launch an interactive shell, so variables exported only from `~/.zshrc` are normally unavailable to it.

## Build and install

```bash
git clone https://github.com/sheneyan/aiquokka-menubar.git
cd aiquokka-menubar
swift test
SIGNING_IDENTITY=- ./scripts/build-app.sh
cp -R dist/aiquokka.app /Applications/
open /Applications/aiquokka.app
```

`SIGNING_IDENTITY=-` produces an ad-hoc signed local build. If it is omitted, the build script uses the first available Apple Development identity and otherwise falls back to ad-hoc signing.

To uninstall, quit aiquokka from its menu and move `/Applications/aiquokka.app` to the Trash. The App does not install background daemons or privileged helpers.

## Notifications

macOS usage notifications are requested only after you choose **Enable** in the App. Alerts are evaluated locally from aiquokka output.

ntfy forwarding is disabled by default. When enabled, the App runs a separately installed `agent-notify` executable and points it to a user-selected configuration file. The server URL, topic, and token stay in that file; the App does not store the ntfy token. The configuration file must have `0600` permissions.

## Privacy and credentials

- Provider requests and credential refresh remain owned by the locally installed aiquokka CLI.
- This App runs `aiquokka --yml` directly and parses its standard output.
- The App does not upload provider usage data or credentials.
- Optional ntfy notifications send only the generated milestone message through the `agent-notify` configuration you provide.
- DeepSeek Keychain bridging and balance-specific display are designed but are not part of the current release.

Review upstream aiquokka documentation for the credentials and remote endpoints used by each provider.

## Current limitations

- The App currently models percentage-based usage windows. Balance-only windows require the planned balance-model work.
- Source builds are locally signed. Developer ID signing, notarization, automatic updates, packaged downloads, and GitHub Releases are not provided yet.
- Replacing an ad-hoc signed build may cause macOS to treat it as a new code identity for permission purposes.
- Provider schemas and endpoints are controlled upstream and may change.

## Development

```bash
swift test
swift test -Xswiftc -warnings-as-errors
SIGNING_IDENTITY=- ./scripts/build-app.sh
codesign --verify --deep --strict dist/aiquokka.app
```

Long-lived design decisions are available in [`docs/design`](docs/design).

## License

Project-authored code and documentation are available under the [MIT License](LICENSE). See [Third-Party Notices](THIRD_PARTY_NOTICES.md) for bundled dependencies and external runtime attribution.
````

- [ ] **Step 2: Check README claims against the current implementation**

Run:

```bash
rg -n '60|80|95|agent-notify|io.github.sheneyan.aiquokka-menubar|--yml' README.md Sources Tests scripts
! rg -n 'DeepSeek.*(supported|available|implemented)|download the latest release|notarized' README.md
```

Expected: evidence exists for the stated refresh and notification behavior; the negative scan prints nothing. Manually confirm the README says DeepSeek support is designed but not released.

- [ ] **Step 3: Verify every README build command locally**

Run from the repository root:

```bash
swift test
SIGNING_IDENTITY=- ./scripts/build-app.sh
codesign --verify --deep --strict dist/aiquokka.app
```

Expected: tests pass, the app builds, and `codesign` exits 0. Do not run the clone, copy-to-Applications, or uninstall instructions against the working checkout.

- [ ] **Step 4: Commit the README**

```bash
git add README.md
git commit -m "docs: add public project readme"
```

### Task 4: Move durable designs and remove internal execution plans

**Files:**
- Create: `docs/design/2026-08-24-aiquokka-menubar-design.md`
- Create: `docs/design/2026-09-01-aiquokka-display-mode-design.md`
- Create: `docs/design/2026-09-04-usage-alerts-design.md`
- Create: `docs/design/2026-09-18-deepseek-keychain-balance-design.md`
- Create: `docs/design/2026-09-18-public-repository-baseline-design.md`
- Delete: `docs/superpowers/specs/*.md`
- Delete: `docs/superpowers/plans/*.md`

- [ ] **Step 1: Move all durable specifications to the public design directory**

Run:

```bash
mkdir -p docs/design
git mv docs/superpowers/specs/2026-08-24-aiquokka-menubar-design.md docs/design/
git mv docs/superpowers/specs/2026-09-01-aiquokka-display-mode-design.md docs/design/
git mv docs/superpowers/specs/2026-09-04-usage-alerts-design.md docs/design/
git mv docs/superpowers/specs/2026-09-18-deepseek-keychain-balance-design.md docs/design/
git mv docs/superpowers/specs/2026-09-18-public-repository-baseline-design.md docs/design/
```

Expected: five tracked design files appear under `docs/design/`.

- [ ] **Step 2: Make retained designs safe and accurate for the public identity**

Apply these exact content changes:

- In `docs/design/2026-08-24-aiquokka-menubar-design.md`, replace the machine-specific command `/Users/sheneyan/go/bin/aiquokka --yml` with `aiquokka --yml`.
- In `docs/design/2026-09-18-deepseek-keychain-balance-design.md`, replace the Keychain service with `io.github.sheneyan.aiquokka-menubar.deepseek`.
- In `docs/design/2026-09-18-public-repository-baseline-design.md`, describe the previous bundle identifier as “the legacy local placeholder” without retaining its literal value, and keep `io.github.sheneyan.aiquokka-menubar` as the only literal bundle identifier.
- Add this line below the title in the DeepSeek design:

```markdown
> Status: approved design; not implemented in the current release.
```

- [ ] **Step 3: Remove tracked internal implementation plans**

Run:

```bash
git rm docs/superpowers/plans/2026-08-24-aiquokka-menubar-implementation.md
git rm docs/superpowers/plans/2026-09-01-aiquokka-display-mode-implementation.md
git rm docs/superpowers/plans/2026-09-04-usage-alerts-implementation.md
git rm docs/superpowers/plans/2026-09-18-public-repository-baseline.md
rmdir docs/superpowers/specs docs/superpowers
```

Expected: `docs/superpowers/` no longer exists. Do not touch untracked `docs/research/`.

- [ ] **Step 4: Verify the public documentation tree**

Run:

```bash
test "$(find docs/design -maxdepth 1 -type f | wc -l | tr -d ' ')" = "5"
test ! -e docs/superpowers
test -f docs/research/2026-09-04-aiquokka-llm-billing-mimo-deepseek.md
! rg -n '/Users/|Documents/Work|com\.local\.aiquokka-menubar' README.md docs/design Sources Tests scripts Package.swift Package.resolved
rg -n 'approved design; not implemented' docs/design/2026-09-18-deepseek-keychain-balance-design.md
```

Expected: all commands exit 0; only the explicit DeepSeek status line is printed.

- [ ] **Step 5: Commit the documentation reorganization**

```bash
git add -A docs/design docs/superpowers
git commit -m "docs: organize public design history"
```

### Task 5: Audit the current tree and full Git history before publication

**Files:**
- Inspect only unless a finding requires a scoped correction.
- Preserve: `docs/research/`

- [ ] **Step 1: Confirm the intended tracked and untracked boundary**

Run:

```bash
git status --short --ignored
git ls-files docs/research
git check-ignore .DS_Store
```

Expected: `.DS_Store` is ignored, `git ls-files docs/research` prints nothing, and `docs/research/` remains untracked. Any other unexpected file stops the publication flow until classified.

- [ ] **Step 2: Run a dedicated secret scanner when available**

Run:

```bash
if command -v gitleaks >/dev/null 2>&1; then
  gitleaks git . --redact --no-banner
else
  echo "gitleaks unavailable; using targeted current-tree and history scans"
fi
```

Expected: gitleaks exits 0, or the explicit fallback message is printed. Do not install an unpinned scanner as part of this release cleanup.

- [ ] **Step 3: Scan the current tracked tree for credential-shaped content and private paths**

Run:

```bash
git grep -nEI '(api[_-]?key|access[_-]?token|refresh[_-]?token|authorization:|bearer[[:space:]]+[A-Za-z0-9._-]{12,}|BEGIN (RSA |EC |OPENSSH )?PRIVATE KEY|sk-[A-Za-z0-9_-]{12,}|/Users/|Documents/Work)'
```

Expected: only explanatory source/docs and clearly synthetic test strings are reported. Inspect every match. A real key, token, private key, endpoint credential, user email, or provider response is a release blocker.

- [ ] **Step 4: Scan all historical patches for the same classes of data**

Run:

```bash
git log --all -p --full-history -- . \
  | rg -n -i '(api[_-]?key|access[_-]?token|refresh[_-]?token|authorization:|bearer\s+[A-Za-z0-9._-]{12,}|BEGIN (RSA |EC |OPENSSH )?PRIVATE KEY|sk-[A-Za-z0-9_-]{12,}|/Users/|Documents/Work)'
git log --all --format='%h %an <%ae>' | sort -u
```

Expected: inspect all matches. The previously approved “retain history” policy permits non-secret historical local paths and the existing local-host commit email, but these must be reported as accepted development traces. Any actual secret or personal provider data stops the push and requires credential rotation plus a separately reviewed history-cleaning decision.

- [ ] **Step 5: Scan fixtures for real-looking provider output**

Run:

```bash
for fixture in Tests/AiQokkaMenubarTests/Fixtures/*; do
  echo "checking $fixture"
  rg -n -i '(email|account|user_id|token|secret|api[_-]?key|balance|currency|endpoint|https?://)' "$fixture" || true
done
```

Expected: no real account identifiers, balances, endpoints, or credentials. Ordinary provider names, percentage values, and obviously synthetic errors are acceptable.

- [ ] **Step 6: Record the audit outcome before continuing**

The execution report must state:

```text
Secret scanner: <gitleaks result or targeted-fallback result>
Current tree: <clean or corrected findings>
Full history: <clean of secrets; accepted local-path/local-host traces if present>
Fixtures: <synthetic-only or corrected findings>
Publication blocker: none
```

Do not create a public audit report file containing matched data. If any correction was required, add only the corrected source/docs files and commit them with `chore: remove publication-sensitive metadata`, then repeat Steps 1-5.

### Task 6: Run the complete release-quality verification

**Files:**
- Verify only.

- [ ] **Step 1: Run all tests with warnings promoted to errors**

Run:

```bash
swift test
swift test -Xswiftc -warnings-as-errors
```

Expected: both commands exit 0 with zero test failures and no compiler warnings.

- [ ] **Step 2: Build and ad-hoc sign the release app**

Run:

```bash
SIGNING_IDENTITY=- CONFIGURATION=release ./scripts/build-app.sh
codesign --verify --deep --strict dist/aiquokka.app
codesign -dv --verbose=4 dist/aiquokka.app 2>&1 | rg 'Identifier=io.github.sheneyan.aiquokka-menubar|Signature=adhoc'
```

Expected: the build succeeds, strict verification exits 0, and both the public identifier and ad-hoc signature are reported.

- [ ] **Step 3: Verify the built bundle metadata and executable**

Run:

```bash
test "$(plutil -extract CFBundleIdentifier raw dist/aiquokka.app/Contents/Info.plist)" = "io.github.sheneyan.aiquokka-menubar"
test "$(plutil -extract LSMinimumSystemVersion raw dist/aiquokka.app/Contents/Info.plist)" = "13.0"
test "$(plutil -extract LSUIElement raw dist/aiquokka.app/Contents/Info.plist)" = "true"
test -x dist/aiquokka.app/Contents/MacOS/AiQokkaMenubar
```

Expected: all assertions exit 0.

- [ ] **Step 4: Perform the final repository consistency checks**

Run:

```bash
git diff --check
test -z "$(git status --short --untracked-files=no)"
test -z "$(git ls-files docs/research)"
test ! -e docs/superpowers
test -f README.md
test -f LICENSE
test -f THIRD_PARTY_NOTICES.md
test "$(find docs/design -maxdepth 1 -type f | wc -l | tr -d ' ')" = "5"
! rg -n '/Users/|Documents/Work|com\.local\.aiquokka-menubar' README.md LICENSE THIRD_PARTY_NOTICES.md docs/design Sources Tests scripts Package.swift Package.resolved
```

Expected: all assertions exit 0. `docs/research/` may still appear as the sole untracked path in a normal `git status --short` and must remain uncommitted.

### Task 7: Connect and publish the empty GitHub repository

**Files:**
- Modify repository-local Git configuration by adding `origin`.
- Write remote `main` only after every prior task passes.

- [ ] **Step 1: Reconfirm GitHub target and empty state immediately before publishing**

Run:

```bash
gh repo view sheneyan/aiquokka-menubar --json nameWithOwner,visibility,isEmpty,url,defaultBranchRef
```

Expected: `nameWithOwner` is `sheneyan/aiquokka-menubar`, visibility is `PUBLIC`, `isEmpty` is `true`, and the URL is `https://github.com/sheneyan/aiquokka-menubar`. If the repository is no longer empty, stop; do not force-push or overwrite it.

- [ ] **Step 2: Add or validate the `origin` remote**

Run:

```bash
if git remote get-url origin >/dev/null 2>&1; then
  test "$(git remote get-url origin)" = "https://github.com/sheneyan/aiquokka-menubar.git"
else
  git remote add origin https://github.com/sheneyan/aiquokka-menubar.git
fi
git remote -v
```

Expected: both fetch and push URLs for `origin` are the exact target repository.

- [ ] **Step 3: Capture the local publication SHA and push without force**

Run:

```bash
publication_sha="$(git rev-parse HEAD)"
git push -u origin main
printf '%s\n' "$publication_sha"
```

Expected: GitHub accepts the new `main` branch and local `main` starts tracking `origin/main`. Never add `--force` or `--force-with-lease`.

- [ ] **Step 4: Verify remote and local commit identity**

Run:

```bash
local_sha="$(git rev-parse HEAD)"
remote_sha="$(git ls-remote origin refs/heads/main | awk '{print $1}')"
test -n "$remote_sha"
test "$local_sha" = "$remote_sha"
git status --short --branch
gh repo view sheneyan/aiquokka-menubar --json defaultBranchRef,url,visibility
```

Expected: local and remote SHAs match, `main` tracks `origin/main`, and the GitHub default branch is `main`. The final status may show untracked `docs/research/` only.

- [ ] **Step 5: Report publication evidence**

The final execution report must include:

```text
Repository: https://github.com/sheneyan/aiquokka-menubar
Published SHA: <verified matching local and remote SHA>
Tests: <fresh total and failures>
Build: dist/aiquokka.app, release, ad-hoc signed
Bundle ID: io.github.sheneyan.aiquokka-menubar
Secret audit: <scanner and fallback coverage, no unresolved blockers>
Preserved local work: docs/research/ remains untracked
Known retained history trace: existing local paths/local-host commit email, no secrets
```
