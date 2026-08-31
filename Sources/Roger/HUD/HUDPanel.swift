import AppKit
import RogerCore
import SwiftUI

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
        panel.collectionBehavior = [
            .canJoinAllSpaces,
            .stationary,
            .fullScreenAuxiliary,
            .ignoresCycle,
        ]
    }

    func render(_ state: DictationState) {
        model.update(state)
        if model.isVisible {
            expand()
        } else {
            collapse()
        }
    }

    func render(bands: [Float]) {
        model.update(bands: bands)
    }

    private func expand() {
        dismissTask?.cancel()
        dismissTask = nil

        if !panel.isVisible {
            reposition()
            // Become visible without activating the app in front of it.
            panel.orderFrontRegardless()
        }
        // No `withAnimation`: the bubble carries its own motion per direction and
        // axis, and one from outside would override all four.
        model.setExpanded(true)
    }

    private func collapse() {
        guard panel.isVisible else { return }

        model.setExpanded(false)

        // Only after the motion, and only if no new dictation started meanwhile.
        dismissTask = Task { [weak self] in
            try? await Task.sleep(for: Design.Bubble.collapseDuration)
            guard let self, !Task.isCancelled, !self.model.isVisible else { return }
            self.panel.orderOut(nil)
        }
    }

    private func reposition() {
        guard let screen = NSScreen.main else { return }
        let visible = screen.visibleFrame
        panel.setFrameOrigin(
            NSPoint(
                x: visible.midX - Metrics.width / 2,
                y: visible.minY + Metrics.bottomInset - Metrics.height / 2
            )
        )
    }
}
