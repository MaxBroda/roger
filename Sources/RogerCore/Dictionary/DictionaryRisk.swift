import Foundation

/// An entry might hit more text than intended. A warning, not a veto — only the
/// owner knows whether `cloud` is an ordinary word or always a misheard `Claude`.
public enum DictionaryRisk: Hashable, Sendable {
    case commonWord(String)
    case tooShort(String)
    /// Glued together the pattern is an ordinary word — and the rule deliberately
    /// allows nothing between the words.
    case gluesIntoCommonWord(String)

    public var message: String {
        switch self {
        case .commonWord(let word):
            "»\(word)« ist ein gewöhnliches Wort. Die Regel greift überall, wo es vorkommt."
        case .tooShort(let word):
            "»\(word)« ist sehr kurz. Kurze Muster treffen leicht etwas Unbeabsichtigtes."
        case .gluesIntoCommonWord(let word):
            "Zusammengeschrieben ergibt das Muster »\(word)« — ein gewöhnliches Wort."
        }
    }
}

/// Words a rule breaks more than it heals. Deliberately *no* domain terms:
/// `Commit` or `Merge` are exactly the words that belong capitalised — warning
/// about them would devalue every other warning.
enum CommonWords {
    static func contains(_ word: String) -> Bool {
        set.contains(word.lowercased())
    }

    private static let set: Set<String> = [
        // German function and everyday words
        "aber", "alle", "alles", "als", "also", "am", "an", "auch", "auf", "aus",
        "bei", "beim", "bin", "bis", "bitte", "da", "damit", "dann", "das", "dass",
        "dem", "den", "der", "des", "die", "dies", "diese", "doch", "dort", "du",
        "durch", "ein", "eine", "einen", "einer", "er", "es", "etwas", "für",
        "ganz", "gut", "hat", "hier", "ich", "ihr", "im", "immer", "in", "ist",
        "ja", "jetzt", "kann", "kein", "klein", "mal", "man", "mehr", "mein",
        "mit", "nach", "nein", "neu", "nicht", "nichts", "nie", "noch", "nun",
        "nur", "ob", "oder", "ohne", "schon", "sehr", "sein", "sich", "sie",
        "sind", "so", "über", "um", "und", "uns", "vom", "von", "vor", "war",
        "was", "weg", "weil", "wenn", "wer", "wie", "wieder", "wir", "wird",
        "wo", "zu", "zum", "zur",
        // English everyday words that collide with product names
        "base", "cash", "cloud", "code", "cost", "count", "even", "form",
        "great", "just", "key", "kind", "less", "letter", "like", "line",
        "link", "list", "mail", "mark", "most", "much", "name", "note", "over",
        "page", "part", "plan", "pool", "port", "quest", "rest", "safe",
        "same", "side", "site", "size", "star", "step", "still", "than",
        "then", "thing", "time", "top", "turn", "use", "very", "want", "watch",
        "way", "well", "word", "work", "world", "would",
    ]
}
