import AppKit
import ApplicationServices
import Foundation

/// Puts the text on the pasteboard briefly and synthesises ⌘V. The detour is the
/// only route that works everywhere — terminals, Electron apps and web text
/// fields handle synthetic single keys unreliably. The previous contents are
/// saved and written back.
public struct PasteboardInjector: TextInjecting {
    /// Until the target app sees the new pasteboard.
    private let settleDelay: Duration
    /// Until the paste is through and we may write back.
    private let restoreDelay: Duration

    public init(
        settleDelay: Duration = .milliseconds(30),
        restoreDelay: Duration = .milliseconds(150)
    ) {
        self.settleDelay = settleDelay
        self.restoreDelay = restoreDelay
    }

    public func inject(_ transcript: Transcript) async throws {
        guard AXIsProcessTrusted() else {
            throw RogerError.accessibilityPermissionDenied
        }

        let pasteboard = NSPasteboard.general

        // With Roger frontmost there is no target and ⌘V would land in the search
        // field next to it. The text stays on the pasteboard instead.
        if await Self.isFrontmost() {
            pasteboard.clearContents()
            pasteboard.setString(transcript.text, forType: .string)
            return
        }

        let snapshot = PasteboardSnapshot(of: pasteboard)

        pasteboard.clearContents()
        pasteboard.setString(transcript.text, forType: .string)

        try await Task.sleep(for: settleDelay)
        try Self.postPasteShortcut()
        try await Task.sleep(for: restoreDelay)

        snapshot.restore(into: pasteboard)
    }

    @MainActor
    private static func isFrontmost() -> Bool {
        NSWorkspace.shared.frontmostApplication?.processIdentifier
            == ProcessInfo.processInfo.processIdentifier
    }

    private static func postPasteShortcut() throws {
        let vKeyCode: CGKeyCode = 9  // kVK_ANSI_V
        guard let source = CGEventSource(stateID: .combinedSessionState),
              let keyDown = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: false)
        else {
            throw RogerError.injectionFailed(reason: "⌘V ließ sich nicht erzeugen.")
        }

        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        // At the HID end, not the session: Raycast, Spotlight and Alfred never see
        // a session-side event, and the text would land behind them.
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
    }
}

/// `clearContents()` invalidates `NSPasteboardItem` objects, so keep the raw data.
private struct PasteboardSnapshot {
    private let items: [[NSPasteboard.PasteboardType: Data]]

    init(of pasteboard: NSPasteboard) {
        items = (pasteboard.pasteboardItems ?? []).map { item in
            var contents: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types {
                contents[type] = item.data(forType: type)
            }
            return contents
        }
    }

    func restore(into pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        guard !items.isEmpty else { return }

        let restored = items.map { contents -> NSPasteboardItem in
            let item = NSPasteboardItem()
            for (type, data) in contents {
                item.setData(data, forType: type)
            }
            return item
        }
        pasteboard.writeObjects(restored)
    }
}
