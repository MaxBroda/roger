import Foundation

/// A non-empty, trimmed dictation text. The invariant lives in the initialiser;
/// `nil` means "nothing was spoken", not an error — errors go through
/// ``RogerError``.
public struct Transcript: Equatable, Sendable, CustomStringConvertible {
    public let text: String

    public init?(_ raw: String) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        self.text = trimmed
    }

    /// For formatters that rewrite the text without emptying it.
    public func replacingText(_ newText: String) -> Transcript {
        Transcript(newText) ?? self
    }

    public var description: String { text }
}
