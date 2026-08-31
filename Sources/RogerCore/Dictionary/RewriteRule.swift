import Foundation

/// A single replacement step: find this word pattern, write that text — what the
/// correction pass actually applies.
public struct RewriteRule: Sendable {
    public let pattern: Phrase
    public let replacement: String
    /// The entry the rule came from — for display in the log.
    public let entryID: UUID
    /// From the misheard form (`true`) or spelling-only (`false`).
    public let fixesMishearing: Bool

    private let regex: NSRegularExpression

    /// Between two words: nothing, whitespace or a hyphen. The `*` rather than `+`
    /// is the point — language models like to glue multi-word names together.
    private static let separator = "[\\s\\-\u{2011}\u{2013}]*"

    /// Right word boundary, so a rule for `Commit` does not fire inside `Commits`.
    /// The left one lives in the correction pass — a lookbehind would grab into
    /// nothing at the start of the search range.
    private static let rightBoundary = "(?![\\p{L}\\p{N}_])"

    public init?(pattern: Phrase, replacement: String, entryID: UUID, fixesMishearing: Bool) {
        let body = pattern.words
            .map(NSRegularExpression.escapedPattern(for:))
            .joined(separator: Self.separator)
        guard let regex = try? NSRegularExpression(
            pattern: body + Self.rightBoundary,
            options: [.caseInsensitive]
        ) else { return nil }

        self.pattern = pattern
        self.replacement = replacement
        self.entryID = entryID
        self.fixesMishearing = fixesMishearing
        self.regex = regex
    }

    /// The correction pass tries the most specific first, so `Claude Code` wins
    /// where `Code` would also match.
    var specificity: Int {
        pattern.words.count * 1_000 + pattern.text.count
    }

    /// Match length at exactly this position. Anchored, because the correction
    /// pass decides where a word boundary is.
    func matchLength(in text: NSString, at index: Int) -> Int? {
        let range = NSRange(location: index, length: text.length - index)
        guard let match = regex.firstMatch(
            in: text as String,
            options: [.anchored, .withoutAnchoringBounds],
            range: range
        ), match.range.length > 0 else { return nil }
        return match.range.length
    }
}
