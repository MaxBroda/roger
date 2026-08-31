/// The dictionary's second half: the first nudges recognition beforehand, this
/// cleans up whatever the nudge missed.
public struct DictionaryCorrector: TextFormatting {
    private let store: DictionaryStore

    public init(store: DictionaryStore) {
        self.store = store
    }

    public func format(_ transcript: Transcript) async throws -> FormattingResult {
        let corrector = TextCorrector(rules: await store.rules)
        let (text, corrections) = corrector.apply(to: transcript.text)
        return FormattingResult(
            transcript: transcript.replacingText(text),
            corrections: corrections
        )
    }
}
