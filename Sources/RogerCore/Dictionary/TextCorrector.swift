import Foundation

/// Applies dictionary rules: one left-to-right pass, at every word boundary the
/// most specific matching rule. Hits never overlap, the longest wins, and a
/// written result is never touched again.
public struct TextCorrector: Sendable {
    private let rules: [RewriteRule]

    /// One of these to the left means we are inside a word.
    private static let wordCharacters: CharacterSet = {
        var set = CharacterSet.alphanumerics
        set.insert(charactersIn: "_")
        return set
    }()

    public init(rules: [RewriteRule]) {
        self.rules = rules
    }

    public func apply(to text: String) -> (text: String, corrections: [AppliedCorrection]) {
        guard !rules.isEmpty else { return (text, []) }

        let source = text as NSString
        var output = ""
        output.reserveCapacity(text.count)

        // A list rather than a dictionary, so the reports follow the order in the
        // text and not the rule order.
        var tally: [(from: String, to: String, count: Int)] = []
        var index = 0

        while index < source.length {
            guard isAtWordStart(index, in: source) else {
                output += source.substring(with: NSRange(location: index, length: 1))
                index += 1
                continue
            }

            var applied = false
            for rule in rules {
                guard let length = rule.matchLength(in: source, at: index) else { continue }
                let found = source.substring(with: NSRange(location: index, length: length))
                output += rule.replacement
                if found != rule.replacement {
                    record(from: found, to: rule.replacement, in: &tally)
                }
                index += length
                applied = true
                break
            }

            if !applied {
                output += source.substring(with: NSRange(location: index, length: 1))
                index += 1
            }
        }

        return (output, tally.map { AppliedCorrection(from: $0.from, to: $0.to, count: $0.count) })
    }

    /// Checked by hand instead of a lookbehind: `NSRegularExpression` would take
    /// the range start for the text start and always agree.
    private func isAtWordStart(_ index: Int, in source: NSString) -> Bool {
        guard index > 0 else { return true }
        guard let scalar = Unicode.Scalar(source.character(at: index - 1)) else { return true }
        return !Self.wordCharacters.contains(scalar)
    }

    private func record(
        from: String,
        to: String,
        in tally: inout [(from: String, to: String, count: Int)]
    ) {
        if let index = tally.firstIndex(where: { $0.from == from && $0.to == to }) {
            tally[index].count += 1
        } else {
            tally.append((from, to, 1))
        }
    }
}
