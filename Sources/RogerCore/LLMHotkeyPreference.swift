import Foundation

/// Remembers the second, LLM-cleanup push-to-talk key across launches — same
/// shape as ``HotkeyPreference``, kept as its own small store rather than
/// teaching that one about roles.
///
/// `@unchecked Sendable`: `UserDefaults` is thread-safe but not annotated as such.
public struct LLMHotkeyPreference: @unchecked Sendable {
    private static let keyCodeKey = "com.mbr.roger.llmHotkey.keyCode"
    private static let thresholdKey = "com.mbr.roger.llmHotkey.holdMilliseconds"

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// F13 — a placeholder the user can freely rebind in Settings; chosen because
    /// it has no default job and, unlike a modifier key, generates a real
    /// `keyDown`/`keyUp` that `HoldKeyMonitor`'s tap actually sees. A modifier
    /// (Command, Option, Control, Shift, Caps Lock, Fn) only ever produces
    /// `flagsChanged`, which the tap does not listen for — pickable in
    /// `HotkeyRecorder` (which does watch `flagsChanged`), but silently inert at
    /// dictation time. That mismatch is a pre-existing gap in `HoldKeyMonitor`,
    /// not something to paper over with a "safer" default alone.
    public static let defaultBinding = HotkeyBinding(
        keyCode: 105,
        holdThreshold: .milliseconds(220),
        replaysShortPress: true
    )

    public var binding: HotkeyBinding {
        guard let stored = defaults.object(forKey: Self.keyCodeKey) as? Int else {
            return Self.defaultBinding
        }
        let milliseconds = defaults.object(forKey: Self.thresholdKey) as? Int
            ?? Int(Self.defaultBinding.holdThreshold.timeInterval * 1000)
        return HotkeyBinding(
            keyCode: UInt16(truncatingIfNeeded: stored),
            holdThreshold: .milliseconds(milliseconds),
            replaysShortPress: HotkeyBinding.needsReplay(keyCode: UInt16(truncatingIfNeeded: stored))
        )
    }

    public func store(_ binding: HotkeyBinding) {
        defaults.set(Int(binding.keyCode), forKey: Self.keyCodeKey)
        defaults.set(Int(binding.holdThreshold.timeInterval * 1000), forKey: Self.thresholdKey)
    }
}
