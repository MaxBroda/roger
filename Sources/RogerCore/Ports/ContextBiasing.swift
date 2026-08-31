/// A transcriber that can be told which words to expect. Separate from
/// ``Transcribing`` because not every backend can do it — and because it is only
/// a nudge; the correction pass is what binds.
public protocol ContextBiasing: Sendable {
    /// Keep it short — see ``PhraseDictionary/biasPhrases(limit:)``.
    func setContextPhrases(_ phrases: [String]) async
}
