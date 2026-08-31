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
    public func append(_ result: FormattingResult) -> DictationRecord {
        let record = DictationRecord(
            text: result.transcript.text,
            corrections: result.corrections
        )
        records.insert(record, at: 0)
        if records.count > limit { records.removeLast(records.count - limit) }
        lifetimeWords += record.wordCount
        persist()
        return record
    }

    public func search(_ query: String) -> [DictationRecord] {
        records.filter { $0.matches(query: query) }
    }

    public func remove(id: UUID) {
        records.removeAll { $0.id == id }
        persist()
    }

    /// Clears the entries, keeps the word total — emptying the store does not
    /// unspeak the words.
    public func clear() {
        records.removeAll()
        persist()
    }

    private func persist() {
        try? file.write(HistoryArchive(lifetimeWords: lifetimeWords, records: records))
    }
}
