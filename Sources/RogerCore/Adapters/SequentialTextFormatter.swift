/// Runs two formatting passes in sequence, feeding the first's output text into
/// the second — dictionary correction (deterministic, auditable) before an LLM
/// cleanup pass (prose-level, no audit trail of its own yet). Merges both
/// correction traces so a dictionary hit still shows in the log even when the
/// LLM path is active.
public struct SequentialTextFormatter: TextFormatting {
    private let first: any TextFormatting
    private let second: any TextFormatting

    public init(_ first: any TextFormatting, then second: any TextFormatting) {
        self.first = first
        self.second = second
    }

    public func format(_ transcript: Transcript) async throws -> FormattingResult {
        let afterFirst = try await first.format(transcript)
        let afterSecond = try await second.format(afterFirst.transcript)
        return FormattingResult(
            transcript: afterSecond.transcript,
            corrections: afterFirst.corrections + afterSecond.corrections
        )
    }
}
