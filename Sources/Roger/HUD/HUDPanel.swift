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
    /// Built fresh for every bubble and dropped afterwards — see ``show()``.
    private var panel: NSPanel?

    private var dismissTask: Task<Void, Never>?
    private var verifyTask: Task<Void, Never>?

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

        // A panel left behind on a Space the user has switched away from still
        // reports itself as visible, so the bubble expanded and animated on a
        // desktop nobody was looking at while the dictation ran.
        if comingUp || panel?.isOnActiveSpace != true {
            if !comingUp {
                Self.log.error("HUD panel was off the active space while visible — rebuilding it.")
            }
            show()
        }
        // No `withAnimation`: the bubble carries its own motion per direction and
        // axis, and one from outside would override all four.
        model.setExpanded(true)
    }

    /// A new panel for every bubble, because a reused one cannot be repaired.
    ///
    /// Measured on 2026-09-08 with Chrome in full-screen: Roger's long-lived
    /// panel was bound to `spaces=[1, 1329]` out of the display's
    /// `[1, 3, 4, 5, 6, 1329]` — the binding of a window *without*
    /// `.canJoinAllSpaces`, pinned to its birth Space and joining full-screen
    /// Spaces only through `.fullScreenAuxiliary`. Ordering it out, re-assigning
    /// the behaviour and ordering it back in did not restore it: the tripwire
    /// logged `isOnActiveSpace=false` one second after exactly that sequence,
    /// three dictations in a row.
    ///
    /// A freshly created panel gets all Spaces every time — proven for this flag
    /// combination, without `.fullScreenAuxiliary`, without `.stationary`, at two
    /// window levels and with an `NSHostingView` as content. So the window is
    /// treated as disposable rather than trusted to keep a behaviour macOS reads
    /// only once, at birth.
    private func show() {
        dismiss()
        let panel = makePanel()
        self.panel = panel
        // Become visible without activating the app in front of it.
        panel.orderFrontRegardless()
        verify(panel)
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: Metrics.width, height: Metrics.height),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.contentView = NSHostingView(rootView: DictationHUDView(model: model))
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.isMovable = false
        panel.hidesOnDeactivate = false
        // ARC owns the panel through `self.panel`; the AppKit-era release on
        // close would over-release it.
        panel.isReleasedWhenClosed = false
        panel.level = .statusBar
        panel.collectionBehavior = Self.collectionBehavior
        panel.setFrameOrigin(origin())
        return panel
    }

    /// The tripwire for the next time the bubble stays away: this is the one
    /// failure the user cannot see, because Roger keeps recording either way.
    /// Delayed on purpose — the Space assignment settles a moment after ordering
    /// in, so checking right away would report every healthy dictation.
    private func verify(_ panel: NSPanel) {
        verifyTask?.cancel()
        verifyTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard let self, !Task.isCancelled, self.model.isVisible, self.panel === panel else { return }
            guard !panel.isOnActiveSpace || !panel.isVisible else { return }
            Self.log.error(
                """
                HUD panel invisible while dictating: \
                isVisible=\(panel.isVisible, privacy: .public) \
                isOnActiveSpace=\(panel.isOnActiveSpace, privacy: .public) \
                frame=\(NSStringFromRect(panel.frame), privacy: .public)
                """
            )
        }
    }

    private func collapse() {
        verifyTask?.cancel()
        verifyTask = nil
        // Before the visibility check: an ordered-out panel would otherwise keep
        // `isExpanded` set, and the next bubble would come up without its motion.
        model.setExpanded(false)
        guard panel != nil else { return }

        // Only after the motion, and only if no new dictation started meanwhile.
        dismissTask = Task { [weak self] in
            try? await Task.sleep(for: Design.Bubble.collapseDuration)
            guard let self, !Task.isCancelled, !self.model.isVisible else { return }
            self.dismiss()
        }
    }

    private func dismiss() {
        panel?.orderOut(nil)
        panel = nil
    }

    private func origin() -> NSPoint {
        // No fallback to the old frame without a screen: keeping it is how the
        // bubble ends up drawing onto a display that is no longer there.
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return .zero }
        let visible = screen.visibleFrame
        return NSPoint(
            x: visible.midX - Metrics.width / 2,
            y: visible.minY + Metrics.bottomInset - Metrics.height / 2
        )
    }
}
