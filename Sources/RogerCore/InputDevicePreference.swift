import Foundation

/// Remembers the chosen input device across launches. Persists the semantic
/// choice (`.automatic`, `.builtIn`, `.explicit(uid:)`), not a numeric device
/// ID — those change between reboots and reconnects. `@unchecked Sendable`:
/// `UserDefaults` is thread-safe but not annotated as such.
public final class InputDevicePreference: @unchecked Sendable {
    private static let modeKey = "com.mbr.roger.inputDevice.mode"
    private static let uidKey = "com.mbr.roger.inputDevice.uid"

    private enum Mode: String {
        case automatic
        case builtIn
        case explicit
    }

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public var selection: InputDeviceSelection {
        get {
            guard
                let raw = defaults.string(forKey: Self.modeKey),
                let mode = Mode(rawValue: raw)
            else {
                // Fresh install and users updating from a version without this
                // preference both land on the recommended default: built-in
                // mic, no forced changes to their setup.
                return .recommendedDefault
            }
            switch mode {
            case .automatic: return .automatic
            case .builtIn: return .builtIn
            case .explicit:
                guard let uid = defaults.string(forKey: Self.uidKey) else {
                    return .recommendedDefault
                }
                return .explicit(uid: uid)
            }
        }
        set { store(newValue) }
    }

    public func store(_ selection: InputDeviceSelection) {
        switch selection {
        case .automatic:
            defaults.set(Mode.automatic.rawValue, forKey: Self.modeKey)
            defaults.removeObject(forKey: Self.uidKey)
        case .builtIn:
            defaults.set(Mode.builtIn.rawValue, forKey: Self.modeKey)
            defaults.removeObject(forKey: Self.uidKey)
        case .explicit(let uid):
            defaults.set(Mode.explicit.rawValue, forKey: Self.modeKey)
            defaults.set(uid, forKey: Self.uidKey)
        }
    }
}
