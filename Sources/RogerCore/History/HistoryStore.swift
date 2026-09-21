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
    private let limit: Int

    private let file: JSONFile<HistoryArchive>

    /// Read on every append rather than captured once: the store outlives the
    /// week it was built in, and a snapshot would stamp Monday's dictations with
    /// the day Roger happened to launch.
    private let now: @Sendable () -> Date

    /// The running week. Private: outside this type it is only ever the saving.
    private var week: WeekTally

    public init(
        fileURL: URL = AppFiles.history,
        now: @escaping @Sendable () -> Date = Date.init,
        limit: Int = 500
    ) {
        self.file = JSONFile(url: fileURL)
        self.limit = limit
        self.now = now
        let archive = ((try? file.read()) ?? nil) ?? .empty
        self.records = archive.records
        self.lifetimeWords = archive.lifetimeWords
        // No tally yet means an archive from before this stat: build one from
        // the entries still in the log, which for the running week is all of
        // them — the cap only bites from the 501st dictation in a week.
        self.week = archive.week ?? Self.tally(ofWeekContaining: now(), in: archive.records)
    }

    /// A store frozen at one date. For tests: they need `append` to stamp an
    /// entry with a date they chose, or an assertion about "next week" starts
    /// depending on the day the suite happens to run.
    convenience init(fileURL: URL, clockAt date: Date, limit: Int = 500) {
        self.init(fileURL: fileURL, now: { date }, limit: limit)
    }

    public var fileURL: URL { file.url }

    @discardableResult
    public func append(_ outcome: DictationOutcome) -> DictationRecord {
        let record = DictationRecord(
            text: outcome.polished.transcript.text,
            rawText: outcome.mode == .llmCleanup ? outcome.raw.text : nil,
            corrections: outcome.polished.corrections,
            duration: outcome.duration,
            recordedAt: now()
        )
        records.insert(record, at: 0)
        if records.count > limit { records.removeLast(records.count - limit) }
        lifetimeWords += record.wordCount
        addToWeek(record, spokenSeconds: outcome.duration, now: record.recordedAt)
        persist()
        return record
    }

    private func addToWeek(_ record: DictationRecord, spokenSeconds: TimeInterval, now: Date) {
        let start = Self.weekStart(containing: now)
        if week.weekStart != start {
            week = WeekTally(weekStart: start, words: 0, spokenSeconds: 0)
        }
        week.words += record.wordCount
        week.spokenSeconds += spokenSeconds
    }

    /// What dictating saved over typing this week's words at `speed`. Zero once
    /// `now` has moved past the counted week — the tally is not rewritten until
    /// the next dictation, and until then it describes a week that is over.
    public func timeSavedThisWeek(typingAt speed: TypingSpeed, now: Date = Date()) -> SavedTime {
        guard week.weekStart == Self.weekStart(containing: now) else {
            return SavedTime(words: 0, spokenSeconds: 0, typingAt: speed)
        }
        return SavedTime(words: week.words, spokenSeconds: week.spokenSeconds, typingAt: speed)
    }

    /// Monday, whatever `Calendar.current` considers the first weekday — that
    /// follows a regional setting, and the readout should not silently mean a
    /// different week on a machine set to US formats.
    public static func weekStart(containing date: Date) -> Date {
        var calendar = Calendar.current
        calendar.firstWeekday = 2
        return calendar.dateInterval(of: .weekOfYear, for: date)?.start ?? date
    }

    /// Entries from before Roger timed a dictation have words but no duration.
    /// Their speech time is estimated rather than taken as zero, which would
    /// credit dictation with their full typing time — and rather than dropping
    /// them, which empties the readout for the week the update lands in. Only
    /// that one week can contain such entries.
    private static func tally(ofWeekContaining now: Date, in records: [DictationRecord]) -> WeekTally {
        let start = weekStart(containing: now)
        let entries = records.filter { weekStart(containing: $0.recordedAt) == start }
        return WeekTally(
            weekStart: start,
            words: entries.reduce(0) { $0 + $1.wordCount },
            spokenSeconds: entries.reduce(0) { $0 + ($1.duration ?? TypingSpeed.spoken.time(forWords: $1.wordCount)) }
        )
    }

    public func search(_ query: String) -> [DictationRecord] {
        records.filter { $0.matches(query: query) }
    }

    public func remove(id: UUID) {
        records.removeAll { $0.id == id }
        persist()
    }

    /// Clears the entries, keeps the totals — emptying the store does not
    /// unspeak the words.
    public func clear() {
        records.removeAll()
        persist()
    }

    private func persist() {
        try? file.write(HistoryArchive(lifetimeWords: lifetimeWords, week: week, records: records))
    }
}
