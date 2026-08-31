import AppKit
import SwiftUI

/// The main window. Transparent title bar, system title off — the window draws
/// its own lettering, because a grey system title on an olive front panel looks
/// like a sticker.
@MainActor
final class MainWindowController: NSObject, NSWindowDelegate {
    private let app: RogerApp
    private var window: NSWindow?

    /// Drives the activation policy: in menu-bar-only mode Roger has to become a
    /// regular app *before* being ordered front, or the window gets no keyboard
    /// focus.
    var onVisibilityWillChange: ((Bool) -> Void)?

    init(app: RogerApp) {
        self.app = app
    }

    var isVisible: Bool { window?.isVisible == true }

    func present() {
        onVisibilityWillChange?(true)

        if let window {
            activate(window)
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 940, height: 660),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Roger"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 780, height: 540)
        // System appearance nailed to dark, or light standard controls — scrollers,
        // focus rings, menus — flash inside the housing.
        window.appearance = NSAppearance(named: .darkAqua)
        window.backgroundColor = NSColor(Design.Palette.background)
        window.contentView = NSHostingView(rootView: MainWindowView(app: app))
        window.delegate = self
        window.setFrameAutosaveName("RogerMainWindow")
        if window.frame.origin == .zero { window.center() }

        self.window = window
        activate(window)
    }

    private func activate(_ window: NSWindow) {
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        onVisibilityWillChange?(false)
    }
}
