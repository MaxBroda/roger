import AppKit
import RogerCore
import SwiftUI
import os

/// The floating window the HUD lives in. What matters is what it does *not* do:
/// take focus — Roger pastes into the frontmost app with ⌘V.
@MainActor
final class HUDPanel {
    /// Fixed size instead of `fittingSize`: on a state change the measurement
    /// happens before SwiftUI has laid out the new state, clipping the capsule to
    /// a rectangle. A generous frame costs nothing, the panel is transparent.
    private enum Metrics {
        static let width: CGFloat = 520
        static let height: CGFloat = 120
        /// Centre of the capsule above the bottom of the usable area — measured
        /// from `visibleFrame`, so the bubble does not hide behind the Dock.
        static let bottomInset: CGFloat = 66
    }

    /// Set again on every show, not once in `init`: macOS reads the behaviour
    /// while a window is being ordered in and ignores it afterwards, so a panel
    /// that lost `canJoinAllSpaces` cannot be repaired by assigning it again.
    private static let collectionBehavior: NSWindow.CollectionBehavior = [
        .canJoinAllSpaces,
        .stationary,
        .fullScreenAuxiliary,
        .ignoresCycle,
    ]

    private static let log = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.mbr.roger",
        category: "hud"
    )

    private let model = HUDModel()
    private let panel: NSPanel

    private var dismissTask: Task<Void, Never>?

    init() {
        let hostingView = NSHostingView(rootView: DictationHUDView(model: model))

        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: Metrics.width, height: Metrics.height),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.contentView = hostingView
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.isMovable = false
        panel.hidesOnDeactivate = false
        panel.level = .statusBar
        panel.collectionBehavior = Self.collectionBehavior
    }

    func render(_ state: DictationState) {
        let wasVisible = model.isVisible
        model.update(state)
        if model.isVisible {
            expand(comingUp: !wasVisible)
        } else {
            collapse()
        }
    }

    func render(bands: [Float]) {
        model.update(bands: bands)
    }

    private func expand(comingUp: Bool) {
        dismissTask?.cancel()
        dismissTask = nil

        // `isVisible` alone would not catch this: a panel left behind on a Space
        // the user has switched away from still reports itself as visible, so the
        // bubble expanded and animated on a desktop nobody was looking at while
        // the dictation ran — and never came back until Roger was restarted.
        if comingUp || !panel.isOnActiveSpace {
            if !comingUp {
                Self.log.error("HUD panel was off the active space while visible — ordering it in again.")
            }
            show()
        }
        // No `withAnimation`: the bubble carries its own motion per direction and
        // axis, and one from outside would override all four.
        model.setExpanded(true)
    }

    /// Out before in, every time. Two reasons, both measured: the collection
    /// behaviour above only takes effect while the window is being ordered in,
    /// and ordering a panel front that sits on another Space drags the whole
    /// desktop over to it instead of bringing the bubble here.
    private func show() {
        panel.orderOut(nil)
        panel.collectionBehavior = Self.collectionBehavior
        reposition()
        // Become visible without activating the app in front of it.
        panel.orderFrontRegardless()
    }

    private func collapse() {
        // Before the `isVisible` check: an ordered-out panel would otherwise keep
        // `isExpanded` set, and the next bubble would come up without its motion.
        model.setExpanded(false)
        guard panel.isVisible else { return }

        // Only after the motion, and only if no new dictation started meanwhile.
        dismissTask = Task { [weak self] in
            try? await Task.sleep(for: Design.Bubble.collapseDuration)
            guard let self, !Task.isCancelled, !self.model.isVisible else { return }
            self.panel.orderOut(nil)
        }
    }

    private func reposition() {
        // No early return without a screen: keeping the old frame is how the
        // bubble ends up drawing onto a display that is no longer there.
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let visible = screen.visibleFrame
        panel.setFrameOrigin(
            NSPoint(
                x: visible.midX - Metrics.width / 2,
                y: visible.minY + Metrics.bottomInset - Metrics.height / 2
            )
        )
    }
}
