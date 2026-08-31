import Foundation

/// A dictionary entry. Two kinds, one record — they differ in whether a misheard
/// form is stored:
///
/// - **Term**: ``written`` only, fixes the spelling.
/// - **Correction**: ``heard`` *and* ``written`` — hears X, writes Y.
public struct DictionaryEntry: Identifiable, Hashable, Sendable {
    public let id: UUID
    public let written: Phrase
    /// `nil` for a plain term.
    public let heard: Phrase?
    public let isEnabled: Bool
    public let createdAt: Date

    public enum Kind: Sendable { case term, correction }

    /// Rejects a pair that is none: `pull requests` → `Pull Requests` is already
    /// covered by the term rule. `ray cast` → `Raycast` stays — the word count
    /// differs, and a single-word term never finds the split form.
    public init?(
        written: Phrase,
        heard: Phrase? = nil,
        isEnabled: Bool = true,
        id: UUID = UUID(),
        createdAt: Date = Date()
    ) {
        if let heard,
           heard.comparisonKey == written.comparisonKey,
           heard.words.count == written.words.count {
            return nil
        }
        self.id = id
        self.written = written
        self.heard = heard
        self.isEnabled = isEnabled
        self.createdAt = createdAt
    }

    public init?(written: String, heard: String = "", isEnabled: Bool = true) {
        guard let written = Phrase(written) else { return nil }
        self.init(written: written, heard: Phrase(heard), isEnabled: isEnabled)
    }

    public var kind: Kind { heard == nil ? .term : .correction }

    /// The pattern that decides the entry's use and its risk.
    public var pattern: Phrase { heard ?? written }

    /// Entries are immutable — an edit produces a new one with the same identity.
    public func with(
        written: Phrase? = nil,
        heard: Phrase?? = nil,
        isEnabled: Bool? = nil
    ) -> DictionaryEntry? {
        DictionaryEntry(
            written: written ?? self.written,
            heard: heard ?? self.heard,
            isEnabled: isEnabled ?? self.isEnabled,
            id: id,
            createdAt: createdAt
        )
    }

    /// A correction yields two steps: one for the misheard form, one for the
    /// target's spelling — the latter is free and covers the common case of a name
    /// heard correctly but written lowercase.
    public var rules: [RewriteRule] {
        guard isEnabled else { return [] }
        var rules: [RewriteRule?] = []
        if let heard {
            rules.append(
                RewriteRule(
                    pattern: heard,
                    replacement: written.text,
                    entryID: id,
                    fixesMishearing: true
                )
            )
        }
        rules.append(
            RewriteRule(
                pattern: written,
                replacement: written.text,
                entryID: id,
                fixesMishearing: false
            )
        )
        return rules.compactMap { $0 }
    }

    /// What looks dangerous about this entry. Empty means harmless.
    public var risks: [DictionaryRisk] {
        var risks: [DictionaryRisk] = []
        let pattern = pattern

        if pattern.isSingleWord {
            let word = pattern.words[0]
            if CommonWords.contains(word) {
                risks.append(.commonWord(word))
            } else if word.count < 4, kind == .correction {
                // Corrections only: a term only spells itself, or every
                // abbreviation would carry a warning.
                risks.append(.tooShort(word))
            }
        } else {
            // Nothing may stand between the words either — if the glued form is a
            // real word, the rule hits it too.
            let glued = pattern.words.joined()
            if CommonWords.contains(glued) {
                risks.append(.gluesIntoCommonWord(glued))
            }
        }
        return risks
    }

    func matches(query: String) -> Bool {
        let needle = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !needle.isEmpty else { return true }
        return written.text.lowercased().contains(needle)
            || heard?.text.lowercased().contains(needle) == true
    }
}

/// Hand-written so the file stays editable by hand: `id` and `created` are
/// optional when reading, `{"written": "Vercel"}` is enough.
extension DictionaryEntry: Codable {
    private enum CodingKeys: String, CodingKey {
        case id, written, heard, enabled, created
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let written = try container.decode(Phrase.self, forKey: .written)
        let heard = try container.decodeIfPresent(Phrase.self, forKey: .heard)
        let enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        let id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        let created = try container.decodeIfPresent(Date.self, forKey: .created) ?? Date()

        guard let entry = DictionaryEntry(
            written: written,
            heard: heard,
            isEnabled: enabled,
            id: id,
            createdAt: created
        ) else {
            throw DecodingError.dataCorruptedError(
                forKey: .heard,
                in: container,
                debugDescription: "»heard« und »written« sind derselbe Ausdruck."
            )
        }
        self = entry
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(written, forKey: .written)
        try container.encodeIfPresent(heard, forKey: .heard)
        try container.encode(isEnabled, forKey: .enabled)
        try container.encode(createdAt, forKey: .created)
    }
}
