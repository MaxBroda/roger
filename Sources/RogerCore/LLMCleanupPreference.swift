import Foundation

/// Whether the second, LLM-cleanup hotkey is wired up at all.
///
/// `@unchecked Sendable`: `UserDefaults` is thread-safe but not annotated as such.
public struct LLMCleanupPreference: @unchecked Sendable {
    private static let key = "com.mbr.roger.llmCleanupEnabled"

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Off by default: an experimental pass over the transcript is not something
    /// to turn on unasked.
    public var isEnabled: Bool {
        defaults.bool(forKey: Self.key)
    }

    public func store(_ isEnabled: Bool) {
        defaults.set(isEnabled, forKey: Self.key)
    }
}
