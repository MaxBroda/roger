import FoundationModels

/// Prose cleanup via Apple's on-device Foundation Models framework — punctuation,
/// paragraphs, filler words and self-corrections. Degrades to a pass-through
/// whenever Apple Intelligence isn't usable: never blocks a dictation on a model
/// that might not be there, same posture as `SpeechTranscriber.isAvailable`
/// elsewhere in Roger.
public struct FoundationModelsFormatter: TextFormatting {
    public init() {}

    public func format(_ transcript: RogerCore.Transcript) async throws -> FormattingResult {
        guard case .available = SystemLanguageModel.default.availability else {
            return FormattingResult(transcript: transcript)
        }

        let session = LanguageModelSession(instructions: Self.instructions)
        do {
            let response = try await session.respond(to: transcript.text)
            guard let cleaned = RogerCore.Transcript(response.content) else {
                return FormattingResult(transcript: transcript)
            }
            return FormattingResult(transcript: cleaned)
        } catch {
            // A generation failure degrades to the untouched transcript — losing
            // the dictation to an LLM hiccup would be worse than skipping cleanup.
            return FormattingResult(transcript: transcript)
        }
    }

    private static let instructions = """
        Du bereitest ein Diktat für die Weitergabe auf: entferne Füllwörter und \
        Selbstkorrekturen, ergänze Interpunktion, Groß-/Kleinschreibung und \
        Absätze. Ändere niemals den fachlichen Inhalt, erfinde nichts hinzu, \
        gib nur den bereinigten Text zurück.
        """
}
