import Foundation

/// A phrase: one word or a sequence. A value object rather than `String`,
/// because the dictionary needs three things — that it is not empty, its words,
/// and a case-insensitive comparison form.
public struct Phrase: Hashable, Sendable, CustomStringConvertible, Codable {
    /// Exactly this spelling ends up in the text.
    public let text: String

    /// `Claude Code` → `["Claude", "Code"]`, `Node.js` → `["Node.js"]` — the dot
    /// does not split, spaces and hyphens do.
    public let words: [String]

    public init?(_ raw: String) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let words = trimmed
            .split { $0.isWhitespace || $0 == "-" || $0 == "\u{2011}" || $0 == "\u{2013}" }
            .map(String.init)
        guard !words.isEmpty else { return nil }
        self.text = trimmed
        self.words = words
    }

    /// Lowercased and without separators: `Claude Code`, `claude-code` and
    /// `CLAUDECODE` collapse onto it.
    public var comparisonKey: String {
        words.joined().lowercased()
    }

    public var isSingleWord: Bool { words.count == 1 }

    public var description: String { text }

    /// A bare string in the JSON file, so the dictionary stays editable in a text
    /// editor.
    public init(from decoder: any Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        guard let phrase = Phrase(raw) else {
            throw DecodingError.dataCorruptedError(
                in: try decoder.singleValueContainer(),
                debugDescription: "Leerer Ausdruck."
            )
        }
        self = phrase
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(text)
    }
}
