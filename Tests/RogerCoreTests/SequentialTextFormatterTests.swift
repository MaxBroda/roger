import Testing

@testable import RogerCore

struct SequentialTextFormatterTests {
    private struct UppercasingFormatter: TextFormatting {
        func format(_ transcript: Transcript) async throws -> FormattingResult {
            FormattingResult(
                transcript: transcript.replacingText(transcript.text.uppercased()),
                corrections: [AppliedCorrection(from: transcript.text, to: transcript.text.uppercased(), count: 1)]
            )
        }
    }

    private struct BracketingFormatter: TextFormatting {
        func format(_ transcript: Transcript) async throws -> FormattingResult {
            FormattingResult(
                transcript: transcript.replacingText("[\(transcript.text)]"),
                corrections: [AppliedCorrection(from: transcript.text, to: "[\(transcript.text)]", count: 1)]
            )
        }
    }

    @Test func führtBeidePässeInReihenfolgeAus() async throws {
        let subject = SequentialTextFormatter(UppercasingFormatter(), then: BracketingFormatter())
        let transcript = try #require(Transcript("hallo"))

        let result = try await subject.format(transcript)

        #expect(result.transcript.text == "[HALLO]")
    }

    @Test func verkettetDieKorrekturenBeiderPässe() async throws {
        let subject = SequentialTextFormatter(UppercasingFormatter(), then: BracketingFormatter())
        let transcript = try #require(Transcript("hallo"))

        let result = try await subject.format(transcript)

        #expect(result.corrections == [
            AppliedCorrection(from: "hallo", to: "HALLO", count: 1),
            AppliedCorrection(from: "HALLO", to: "[HALLO]", count: 1),
        ])
    }
}
