import Foundation

/// Regular app (Dock icon, app switcher, window on launch) or menu bar only —
/// there the key works and the window arrives on request.
///
/// `@unchecked Sendable`: `UserDefaults` is thread-safe but not annotated as such.
public struct MenuBarModePreference: @unchecked Sendable {
    private static let key = "com.mbr.roger.menuBarOnly"

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Default is the regular app — the first launch should show something.
    public var isMenuBarOnly: Bool {
        defaults.bool(forKey: Self.key)
    }

    public func store(_ isMenuBarOnly: Bool) {
        defaults.set(isMenuBarOnly, forKey: Self.key)
    }
}
