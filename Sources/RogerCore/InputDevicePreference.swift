import Foundation

/// Remembers the chosen input device across launches. Persists the semantic
/// choice (`.automatic`, `.builtIn`, `.explicit(uid:)`), not a numeric device
/// ID — those change between reboots and reconnects. `@unchecked Sendable`:
/// `UserDefaults` is thread-safe but not annotated as such.
public final class InputDevicePreference: @unchecked Sendable {
    private static let modeKey = "com.mbr.roger.inputDevice.mode"
    private static let uidKey = "com.mbr.roger.inputDevice.uid"
    /// Only a label, never identity: the name a pinned device had when it was
    /// picked, so the UI can say *which* device is missing while it is away.
    private static let labelKey = "com.mbr.roger.inputDevice.label"

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

    /// The name the pinned device had when it was chosen. `nil` for every other
    /// selection, and for a pin stored by a version that did not remember it.
    public var pinnedLabel: String? {
        guard case .explicit = selection else { return nil }
        return defaults.string(forKey: Self.labelKey)
    }

    public func store(_ selection: InputDeviceSelection, label: String? = nil) {
        switch selection {
        case .automatic:
            defaults.set(Mode.automatic.rawValue, forKey: Self.modeKey)
            defaults.removeObject(forKey: Self.uidKey)
            defaults.removeObject(forKey: Self.labelKey)
        case .builtIn:
            defaults.set(Mode.builtIn.rawValue, forKey: Self.modeKey)
            defaults.removeObject(forKey: Self.uidKey)
            defaults.removeObject(forKey: Self.labelKey)
        case .explicit(let uid):
            defaults.set(Mode.explicit.rawValue, forKey: Self.modeKey)
            defaults.set(uid, forKey: Self.uidKey)
            if let label {
                defaults.set(label, forKey: Self.labelKey)
            } else {
                defaults.removeObject(forKey: Self.labelKey)
            }
        }
    }
}
