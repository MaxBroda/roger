import Foundation

/// All dictionary entries, one per pattern. Yields the rules for the correction
/// pass and the list for recognition biasing.
public struct PhraseDictionary: Sendable, Equatable {
    public private(set) var entries: [DictionaryEntry]

    public init(entries: [DictionaryEntry] = []) {
        self.entries = []
        for entry in entries { upsert(entry) }
    }

    /// Inserts or replaces — by identity, else by pattern. The second path keeps
    /// two contradicting rules from sitting side by side with sort order deciding.
    @discardableResult
    public mutating func upsert(_ entry: DictionaryEntry) -> Bool {
        if let index = entries.firstIndex(where: { $0.id == entry.id }) {
            entries[index] = entry
            return true
        }
        if let index = entries.firstIndex(where: { $0.matchKey == entry.matchKey }) {
            entries[index] = entry
            return true
        }
        entries.append(entry)
        return true
    }

    public mutating func remove(id: UUID) {
        entries.removeAll { $0.id == id }
    }

    public func entry(id: UUID) -> DictionaryEntry? {
        entries.first { $0.id == id }
    }

    /// Another entry with the same pattern, if there is one.
    public func conflict(with entry: DictionaryEntry) -> DictionaryEntry? {
        entries.first { $0.id != entry.id && $0.matchKey == entry.matchKey }
    }

    /// Corrections first, then alphabetical — the pairs are what someone looks up
    /// when something comes out wrong.
    public func search(_ query: String) -> [DictionaryEntry] {
        entries
            .filter { $0.matches(query: query) }
            .sorted { lhs, rhs in
                if lhs.kind != rhs.kind { return lhs.kind == .correction }
                return lhs.written.text.localizedCaseInsensitiveCompare(rhs.written.text) == .orderedAscending
            }
    }

    public var terms: [DictionaryEntry] { entries.filter { $0.kind == .term } }
    public var corrections: [DictionaryEntry] { entries.filter { $0.kind == .correction } }

    /// Most specific first — the sort *is* the "longest match wins" semantics,
    /// because the correction pass takes the first hit.
    public var rules: [RewriteRule] {
        entries
            .flatMap(\.rules)
            .sorted { lhs, rhs in
                if lhs.specificity != rhs.specificity { return lhs.specificity > rhs.specificity }
                // At equal length the misheard form counts more — it changes something.
                return lhs.fixesMishearing && !rhs.fixesMishearing
            }
    }

    /// The context for recognition. Kept short, because a long context makes these
    /// models invent words on unclear audio. Multi-word phrases go first — they
    /// are harder to hit and gain the most.
    public func biasPhrases(limit: Int = 60) -> [String] {
        let enabled = entries.filter(\.isEnabled)
        let sorted = enabled.sorted { lhs, rhs in
            let lhsWords = lhs.written.words.count
            let rhsWords = rhs.written.words.count
            if lhsWords != rhsWords { return lhsWords > rhsWords }
            return lhs.createdAt > rhs.createdAt
        }
        var seen = Set<String>()
        var result: [String] = []
        for entry in sorted {
            let text = entry.written.text
            guard seen.insert(text.lowercased()).inserted else { continue }
            result.append(text)
            if result.count == limit { break }
        }
        return result
    }
}

extension DictionaryEntry {
    /// Pattern identity, independent of case and separators.
    var matchKey: String {
        "\(kind == .correction ? "c" : "t"):\(pattern.comparisonKey)"
    }
}
