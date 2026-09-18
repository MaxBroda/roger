import Foundation

/// How fast the user types — what the saved-time readout compares dictation to.
///
/// `@unchecked Sendable`: `UserDefaults` is thread-safe but not annotated as such.
public struct TypingSpeedPreference: @unchecked Sendable {
    private static let key = "com.mbr.roger.typingWordsPerMinute"

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public var speed: TypingSpeed {
        let stored = defaults.integer(forKey: Self.key)
        return stored == 0 ? .default : TypingSpeed(wordsPerMinute: stored)
    }

    public func store(_ speed: TypingSpeed) {
        defaults.set(speed.wordsPerMinute, forKey: Self.key)
    }
}
