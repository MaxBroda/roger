import AppKit
import RogerCore
import SwiftUI

@MainActor
final class OnboardingWindow: NSObject, NSWindowDelegate {
    private let model = OnboardingModel()
    private var window: NSWindow?

    /// Called once all permissions are in place and the window closes.
    var onCompleted: (() -> Void)?

    var onVisibilityWillChange: ((Bool) -> Void)?

    var isComplete: Bool { model.snapshot.isComplete }

    var isVisible: Bool { window?.isVisible == true }

    func present() {
        onVisibilityWillChange?(true)
        model.refresh()

        if let window {
            activate(window)
            model.startPolling()
            return
        }

        let hostingView = NSHostingView(
            rootView: OnboardingView(model: model, onFinish: { [weak self] in self?.close() })
        )
        hostingView.sizingOptions = [.intrinsicContentSize]

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 360),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Roger einrichten"
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        // This window follows the system, not Roger's housing — see ``OnboardingView``.
        window.contentView = hostingView
        window.delegate = self
        window.setContentSize(hostingView.fittingSize)
        window.center()

        self.window = window
        activate(window)
        model.startPolling()
    }

    func close() {
        window?.close()
    }

    private func activate(_ window: NSWindow) {
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        model.stopPolling()
        onVisibilityWillChange?(false)
        if model.snapshot.isComplete {
            onCompleted?()
        }
    }
}
