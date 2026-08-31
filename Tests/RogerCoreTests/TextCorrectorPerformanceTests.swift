import Foundation
import Testing

@testable import RogerCore

/// The correction pass tries every rule at every word boundary — quadratic on
/// paper and still fine as long as it stays fast. This pins down what "fast
/// enough" means, so a growing dictionary cannot quietly add a second between
/// speaking and pasting.
struct TextCorrectorPerformanceTests {
    @Test func bleibtUnterEinerZehntelSekundeProDiktat() {
        let dictionary = PhraseDictionary(entries: DictionarySeed.entries)
        let corrector = TextCorrector(rules: dictionary.rules)
        // About a thousand characters — a long dictation.
        let text = String(
            repeating: "Ich starte cloud code und mache einen kommit im Repository, dann ein pull rikwest. ",
            count: 12
        )

        let start = ContinuousClock.now
        _ = corrector.apply(to: text)
        let elapsed = ContinuousClock.now - start

        #expect(elapsed < .milliseconds(100))
    }
}
