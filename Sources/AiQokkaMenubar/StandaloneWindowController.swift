import AppKit
import SwiftUI

@MainActor
final class StandaloneWindowController: NSObject, NSWindowDelegate {
    static let windowIdentifier = NSUserInterfaceItemIdentifier("com.local.aiquokka.standalone-window")
    static let frameAutosaveName = NSWindow.FrameAutosaveName("AiQokkaStandaloneWindow")

    private let store: UsageStore
    private let displayMode: DisplayModeSettings
    private let alertCoordinator: UsageAlertCoordinator
    private let ntfySettings: UsageNtfySettings
    private let deepSeekSettings: DeepSeekSettings
    private var closingForModeChange = false
    private var terminating = false

    private(set) var window: NSWindow?

    init(
        store: UsageStore,
        displayMode: DisplayModeSettings,
        alertCoordinator: UsageAlertCoordinator,
        ntfySettings: UsageNtfySettings,
        deepSeekSettings: DeepSeekSettings
    ) {
        self.store = store
        self.displayMode = displayMode
        self.alertCoordinator = alertCoordinator
        self.ntfySettings = ntfySettings
        self.deepSeekSettings = deepSeekSettings
        super.init()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applicationWillTerminate(_:)),
            name: NSApplication.willTerminateNotification,
            object: NSApplication.shared
        )
    }

    @objc private func applicationWillTerminate(_ notification: Notification) {
        terminating = true
    }

    func show() {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let hostedView = UsagePopoverView(
            store: store,
            displayMode: displayMode,
            alertCoordinator: alertCoordinator,
            ntfySettings: ntfySettings,
            deepSeekSettings: deepSeekSettings,
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
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: fittingHeight),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "aiquokka"
        window.identifier = Self.windowIdentifier
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.contentViewController = hostingController
        window.setFrameAutosaveName(Self.frameAutosaveName)
        if !window.setFrameUsingName(Self.frameAutosaveName) {
            window.center()
        }

        self.window = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func close() {
        guard let window else { return }

        closingForModeChange = true
        window.close()
        closingForModeChange = false
    }

    func windowWillClose(_ notification: Notification) {
        window = nil

        guard !closingForModeChange,
              !terminating,
              displayMode.mode == .standaloneWindow else {
            return
        }

        displayMode.mode = .menuBar
    }
}
