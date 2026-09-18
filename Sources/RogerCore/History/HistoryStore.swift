import Foundation
import Observation

/// The dictation log — local only, a file next to the dictionary.
@MainActor
@Observable
public final class HistoryStore {
    /// Newest first.
    public private(set) var records: [DictationRecord] = []
    /// Every word ever dictated, including those from evicted entries.
    public private(set) var lifetimeWords: Int = 0

    /// Capped, because the file is rewritten in full after every dictation.
    private let limit = 500

    private let file: JSONFile<HistoryArchive>

    public init(fileURL: URL = AppFiles.history) {
        self.file = JSONFile(url: fileURL)
        let archive = ((try? file.read()) ?? nil) ?? .empty
        self.records = archive.records
        self.lifetimeWords = archive.lifetimeWords
    }

    public var fileURL: URL { file.url }

    @discardableResult
    public func append(_ outcome: DictationOutcome) -> DictationRecord {
        let record = DictationRecord(
            text: outcome.polished.transcript.text,
            rawText: outcome.mode == .llmCleanup ? outcome.raw.text : nil,
            corrections: outcome.polished.corrections,
            duration: outcome.duration
        )
        records.insert(record, at: 0)
        if records.count > limit { records.removeLast(records.count - limit) }
        lifetimeWords += record.wordCount
        persist()
        return record
    }

    /// What dictating saved over typing this week's words at `speed`.
    ///
    /// Entries from before Roger timed a dictation have words but no duration.
    /// Their speech time is estimated rather than taken as zero, which would
    /// credit dictation with their full typing time — and rather than dropping
    /// them, which in the week of the update itself empties the readout. Only
    /// that one week can contain them.
    public func timeSavedThisWeek(typingAt speed: TypingSpeed, now: Date = Date()) -> SavedTime {
        let week = Self.week(containing: now)
        let entries = records.filter { week.contains($0.recordedAt) }
        return SavedTime(
            words: entries.reduce(0) { $0 + $1.wordCount },
            spokenSeconds: entries.reduce(0) { $0 + ($1.duration ?? TypingSpeed.spoken.time(forWords: $1.wordCount)) },
            typingAt: speed
        )
    }

    /// Monday to Sunday, whatever `Calendar.current` considers the first weekday
    /// — that follows a system setting, and the readout should not silently mean
    /// a different week on a machine set to US regional formats.
    private static func week(containing date: Date) -> DateInterval {
        var calendar = Calendar.current
        calendar.firstWeekday = 2
        return calendar.dateInterval(of: .weekOfYear, for: date)
            ?? DateInterval(start: date, duration: 0)
    }

    public func search(_ query: String) -> [DictationRecord] {
        records.filter { $0.matches(query: query) }
    }

    public func remove(id: UUID) {
        records.removeAll { $0.id == id }
        persist()
    }

    /// Clears the entries, keeps the word total — emptying the store does not
    /// unspeak the words. The week's saving goes with the entries, because that
    /// is what it is computed from.
    public func clear() {
        records.removeAll()
        persist()
    }

    private func persist() {
        try? file.write(HistoryArchive(lifetimeWords: lifetimeWords, records: records))
    }
}
