import Foundation

/// What the correction pass changed. For the log: a text that is right otherwise
/// looks exactly like one that was never wrong.
public struct AppliedCorrection: Hashable, Sendable, Codable {
    public let from: String
    public let to: String
    public let count: Int

    public init(from: String, to: String, count: Int) {
        self.from = from
        self.to = to
        self.count = count
    }

    public var description: String {
        count > 1 ? "\(from) → \(to) (\(count)×)" : "\(from) → \(to)"
    }
}

/// The finished text and the trace of what it took.
public struct FormattingResult: Sendable, Equatable {
    public let transcript: Transcript
    public let corrections: [AppliedCorrection]

    public init(transcript: Transcript, corrections: [AppliedCorrection] = []) {
        self.transcript = transcript
        self.corrections = corrections
    }
}
