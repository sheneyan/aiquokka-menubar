import AppKit
import SwiftUI

@MainActor
final class StandaloneWindowController: NSObject, NSWindowDelegate {
    static let windowIdentifier = NSUserInterfaceItemIdentifier("com.local.aiquokka.standalone-window")
    static let frameAutosaveName = NSWindow.FrameAutosaveName("AiQokkaStandaloneWindow")

    private let store: UsageStore
    private let displayMode: DisplayModeSettings
    private var closingForModeChange = false
    private var terminating = false
    private var terminationObserver: NSObjectProtocol?

    private(set) var window: NSWindow?

    init(store: UsageStore, displayMode: DisplayModeSettings) {
        self.store = store
        self.displayMode = displayMode
        super.init()

        terminationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: NSApplication.shared,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.terminating = true
            }
        }
    }

    deinit {
        if let terminationObserver {
            NotificationCenter.default.removeObserver(terminationObserver)
        }
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
