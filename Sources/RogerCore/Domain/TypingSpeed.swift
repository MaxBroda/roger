import Foundation

/// A typing speed in words per minute — the yardstick the saved-time readout
/// measures dictation against.
public struct TypingSpeed: Equatable, Sendable {
    /// The band the setting offers. Clamped rather than rejected: the value also
    /// comes back from `UserDefaults`, where anything may have been written, and
    /// a speed of zero would send the division to infinity.
    public static let range = 20...200

    public static let `default` = TypingSpeed(wordsPerMinute: 40)

    /// How fast speech runs. Not a setting — it stands in for the speech time of
    /// dictations recorded before Roger measured it.
    public static let spoken = TypingSpeed(wordsPerMinute: 130)

    public let wordsPerMinute: Int

    public init(wordsPerMinute: Int) {
        self.wordsPerMinute = min(max(wordsPerMinute, Self.range.lowerBound), Self.range.upperBound)
    }

    public func time(forWords words: Int) -> TimeInterval {
        TimeInterval(words) / TimeInterval(wordsPerMinute) * 60
    }
}
