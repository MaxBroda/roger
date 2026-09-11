/// Which formatting path a dictation ran through — picked per press, not per
/// session, so a second hotkey can pick the LLM cleanup pass without a second
/// `DictationSession`.
public enum DictationMode: Sendable, Equatable {
    case standard
    case llmCleanup
}

/// A finished dictation, before and after formatting — kept together so the
/// LLM path can hand both versions to history (`docs/ideen.md` §1c: a model
/// can lose content, so the raw transcript stays available).
public struct DictationOutcome: Sendable {
    public let raw: Transcript
    public let polished: FormattingResult
    public let mode: DictationMode

    public init(raw: Transcript, polished: FormattingResult, mode: DictationMode) {
        self.raw = raw
        self.polished = polished
        self.mode = mode
    }
}
