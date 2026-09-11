import Foundation

/// A finished dictation as it appears in the log.
public struct DictationRecord: Identifiable, Hashable, Sendable, Codable {
    public let id: UUID
    public let recordedAt: Date
    public let text: String
    /// The transcript before the LLM cleanup pass touched it. `nil` for the
    /// standard path — a model can lose content, so both versions stay
    /// available when it ran (`docs/ideen.md` §1c).
    public let rawText: String?
    public let corrections: [AppliedCorrection]

    public init(
        text: String,
        rawText: String? = nil,
        corrections: [AppliedCorrection] = [],
        id: UUID = UUID(),
        recordedAt: Date = Date()
    ) {
        self.id = id
        self.recordedAt = recordedAt
        self.text = text
        self.rawText = rawText
        self.corrections = corrections
    }

    /// Anything separated by whitespace — punctuation sticks to its word.
    public var wordCount: Int {
        text.split { $0.isWhitespace || $0.isNewline }.count
    }

    func matches(query: String) -> Bool {
        let needle = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !needle.isEmpty else { return true }
        return text.lowercased().contains(needle)
            || corrections.contains { $0.from.lowercased().contains(needle) || $0.to.lowercased().contains(needle) }
    }
}

/// The word total is stored rather than derived: the log is capped, the total is
/// not meant to be.
struct HistoryArchive: Codable, Sendable {
    var lifetimeWords: Int
    var records: [DictationRecord]

    static let empty = HistoryArchive(lifetimeWords: 0, records: [])
}
