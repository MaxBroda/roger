import Foundation

/// The push-to-talk key and its hold time. The threshold is the price of using
/// an ordinary key for PTT: a short press is held back and replayed on release
/// (see ``HoldKeyMonitor``) — the higher the threshold, the more sluggish the key
/// feels otherwise.
public struct HotkeyBinding: Equatable, Sendable {
    /// Virtual key code (Carbon `kVK_*`).
    public let keyCode: UInt16
    public let holdThreshold: Duration
    /// Mandatory for Esc — otherwise Esc is dead system-wide.
    public let replaysShortPress: Bool

    public init(keyCode: UInt16, holdThreshold: Duration, replaysShortPress: Bool) {
        self.keyCode = keyCode
        self.holdThreshold = holdThreshold
        self.replaysShortPress = replaysShortPress
    }

    /// Default binding.
    public static let escHold = HotkeyBinding(
        keyCode: 53,
        holdThreshold: .milliseconds(220),
        replaysShortPress: true
    )

    /// Modifier keys have no job of their own. Every other key does, and Roger
    /// must not take it away.
    public static func needsReplay(keyCode: UInt16) -> Bool {
        !modifierKeyCodes.contains(keyCode)
    }

    /// Shift, control, option, command (left and right), caps lock and fn.
    private static let modifierKeyCodes: Set<UInt16> = [54, 55, 56, 57, 58, 59, 60, 61, 62, 63]

    /// Letters and digits are excluded: bind `A` and every `A` waits out the hold
    /// time afterwards.
    public static func isUsable(keyCode: UInt16) -> Bool {
        !typingKeyCodes.contains(keyCode)
    }

    /// Letters, digits, punctuation, space, delete and return.
    private static let typingKeyCodes: Set<UInt16> = {
        var codes: Set<UInt16> = [
            0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 11, 12, 13, 14, 15, 16, 17,
            19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32, 33, 34, 35,
            37, 38, 39, 40, 41, 42, 43, 44, 45, 46, 47, 50,
        ]
        codes.formUnion([36, 48, 49, 51, 52, 76])  // Zeilenschalter, Tab, Leerzeichen, Rückschritt
        return codes
    }()
}

public extension Duration {
    /// As fractional seconds, the way `DispatchSourceTimer` wants it.
    var timeInterval: TimeInterval {
        let (seconds, attoseconds) = components
        return TimeInterval(seconds) + TimeInterval(attoseconds) / 1e18
    }
}
