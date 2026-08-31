import Foundation
import Testing

@testable import RogerCore

/// The correction pass tries every rule at every word boundary — quadratic on
/// paper and still fine as long as it stays fast. These tests pin down what "fast
/// enough" means, so a growing dictionary cannot quietly add a second between
/// speaking and pasting.
///
/// Wall-clock budgets are machine-dependent, and CI runners are several times
/// slower than the Mac Roger runs on. Both tests therefore take the fastest of
/// several runs — noise only ever makes a measurement slower — and the budget is
/// set to catch an order-of-magnitude regression, not a few milliseconds.
struct TextCorrectorPerformanceTests {
    private static let budget = Duration.milliseconds(500)

    private static func corrector() -> TextCorrector {
        TextCorrector(rules: PhraseDictionary(entries: DictionarySeed.entries).rules)
    }

    /// About a thousand characters — a long dictation.
    private static func dictation(times: Int = 12) -> String {
        String(
            repeating: "Ich starte cloud code und mache einen kommit im Repository, dann ein pull rikwest. ",
            count: times
        )
    }

    private static func fastestRun(of corrector: TextCorrector, on text: String) -> Duration {
        var fastest: Duration?
        for _ in 0..<5 {
            let start = ContinuousClock.now
            _ = corrector.apply(to: text)
            let elapsed = ContinuousClock.now - start
            fastest = fastest.map { min($0, elapsed) } ?? elapsed
        }
        return fastest!
    }

    private static func seconds(_ duration: Duration) -> Double {
        let parts = duration.components
        return Double(parts.seconds) + Double(parts.attoseconds) * 1e-18
    }

    @Test func bleibtUnterEinerHalbenSekundeProDiktat() {
        let elapsed = Self.fastestRun(of: Self.corrector(), on: Self.dictation())

        #expect(elapsed < Self.budget)
    }

    /// The machine-independent half of the statement: four times the text must
    /// not cost sixteen times the time. Linear would be 4×, quadratic 16× — the
    /// limit sits between the two, far enough from either for runner noise.
    @Test func waechstNichtQuadratischMitDerTextlaenge() {
        let corrector = Self.corrector()
        let short = Self.fastestRun(of: corrector, on: Self.dictation())
        let long = Self.fastestRun(of: corrector, on: Self.dictation(times: 48))

        let ratio = Self.seconds(long) / Self.seconds(short)
        #expect(ratio < 8, "4× the text took \(ratio)× the time")
    }
}
