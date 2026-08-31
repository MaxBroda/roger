import Foundation

/// Remembers the push-to-talk key across launches. `@unchecked Sendable`:
/// `UserDefaults` is thread-safe but not annotated as such.
public struct HotkeyPreference: @unchecked Sendable {
    private static let keyCodeKey = "com.mbr.roger.hotkey.keyCode"
    private static let thresholdKey = "com.mbr.roger.hotkey.holdMilliseconds"

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public var binding: HotkeyBinding {
        guard let stored = defaults.object(forKey: Self.keyCodeKey) as? Int else {
            return .escHold
        }
        let milliseconds = defaults.object(forKey: Self.thresholdKey) as? Int
            ?? Int(HotkeyBinding.escHold.holdThreshold.timeInterval * 1000)
        return HotkeyBinding(
            keyCode: UInt16(truncatingIfNeeded: stored),
            holdThreshold: .milliseconds(milliseconds),
            // A property of the key, not a preference: Esc needs it, a modifier
            // has no job of its own and does not.
            replaysShortPress: HotkeyBinding.needsReplay(keyCode: UInt16(truncatingIfNeeded: stored))
        )
    }

    public func store(_ binding: HotkeyBinding) {
        defaults.set(Int(binding.keyCode), forKey: Self.keyCodeKey)
        defaults.set(Int(binding.holdThreshold.timeInterval * 1000), forKey: Self.thresholdKey)
    }
}
