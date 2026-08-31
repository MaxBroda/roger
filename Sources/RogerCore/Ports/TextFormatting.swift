/// Post-processing of the raw transcript — dictionary, later filler words,
/// punctuation, an LLM pass. The result also carries the trace of its changes, or
/// the log could not show whether the dictionary bit.
public protocol TextFormatting: Sendable {
    func format(_ transcript: Transcript) async throws -> FormattingResult
}
