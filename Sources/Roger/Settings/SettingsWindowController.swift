import AppKit
import SwiftUI

/// The settings window. Reachable via ⌘, like in any Mac app.
@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    private let app: RogerApp
    private var window: NSWindow?

    var onVisibilityWillChange: ((Bool) -> Void)?

    init(app: RogerApp) {
        self.app = app
    }

    var isVisible: Bool { window?.isVisible == true }

    func present() {
        onVisibilityWillChange?(true)

        if let window {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            return
        }

        let hostingView = NSHostingView(rootView: SettingsView(app: app))
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 740),
            // No `.resizable`: the content is a fixed list, and a draggable window
            // would promise room it cannot fill.
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Einstellungen"
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .darkAqua)
        window.backgroundColor = NSColor(Design.Palette.background)
        window.contentView = hostingView
        window.delegate = self
        window.center()

        self.window = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        onVisibilityWillChange?(false)
    }
}
