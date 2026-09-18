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
