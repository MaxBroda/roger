import Foundation

/// The user's choice of input device. Persisted as a small tagged enum so we
/// can distinguish "follow system default" (`.automatic`), "always built-in"
/// (`.builtIn`) and a concrete device pinned by UID.
public enum InputDeviceSelection: Equatable, Sendable {
    /// Follow whatever the macOS default input device is at the time of
    /// recording. Not recommended for BT-heavy setups because the default
    /// often points at AirPods once they connect.
    case automatic

    /// Always try to use the internal microphone. Falls back to `.automatic`
    /// if no built-in device is present (Mac Pro, external-only setups).
    case builtIn

    /// A specific device the user pinned. `uid` is CoreAudio's stable UID.
    case explicit(uid: String)

    /// Roger's recommendation for a fresh install: prefer built-in when
    /// available, without forcing anything on setups that don't have one.
    public static let recommendedDefault: InputDeviceSelection = .builtIn
}
