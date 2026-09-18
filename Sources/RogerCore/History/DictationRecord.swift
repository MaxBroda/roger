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
    /// How long the key was held for this dictation. `nil` for entries written
    /// before Roger measured it — a required field would fail the decode of
    /// every one of them, and the log would silently start over empty.
    public let duration: TimeInterval?

    public init(
        text: String,
        rawText: String? = nil,
        corrections: [AppliedCorrection] = [],
        duration: TimeInterval? = nil,
        id: UUID = UUID(),
        recordedAt: Date = Date()
    ) {
        self.id = id
        self.recordedAt = recordedAt
        self.text = text
        self.rawText = rawText
        self.corrections = corrections
        self.duration = duration
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

/// The running week, stored rather than derived from `records` for the same
/// reason as the word total: the log is capped at 500 entries, and a heavy week
/// reaches that. Words and speech time rather than a finished saving, so a
/// typing speed changed on Friday still applies to Monday.
struct WeekTally: Codable, Sendable, Equatable {
    var weekStart: Date
    var words: Int
    var spokenSeconds: TimeInterval

    static let none = WeekTally(weekStart: .distantPast, words: 0, spokenSeconds: 0)
}

/// The totals are stored rather than derived: the log is capped, they are not
/// meant to be.
struct HistoryArchive: Codable, Sendable {
    var lifetimeWords: Int
    /// Optional for the same reason as ``DictationRecord/duration``: archives
    /// written before the saved-time stat exist, and a failed decode is
    /// indistinguishable from a first launch.
    var week: WeekTally?
    var records: [DictationRecord]

    static let empty = HistoryArchive(lifetimeWords: 0, week: .none, records: [])
}
