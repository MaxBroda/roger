import Foundation

/// What dictating saved over typing the same words.
public struct SavedTime: Equatable, Sendable {
    public let seconds: TimeInterval

    /// Clamped at zero: someone who speaks slower than they type has not lost
    /// time, they have only failed to gain any — and a negative readout invites
    /// arithmetic nobody wants to see.
    public init(words: Int, spokenSeconds: TimeInterval, typingAt speed: TypingSpeed) {
        self.seconds = max(0, speed.time(forWords: words) - spokenSeconds)
    }

    /// An em dash while nothing has been saved: a `0min` reads as a
    /// measurement, the dash as the absence of one.
    public var label: String {
        let minutes = Int(seconds / 60)
        guard minutes > 0 else { return seconds < 1 ? "—" : "< 1min" }
        guard minutes >= 60 else { return "\(minutes)min" }
        return "\(minutes / 60):\(String(format: "%02d", minutes % 60))h"
    }
}
