import Foundation
import Testing

@testable import RogerCore

struct TypingSpeedTests {
    @Test(arguments: [
        (0, 20),
        (19, 20),
        (20, 20),
        (40, 40),
        (200, 200),
        (201, 200),
        (100_000, 200),
        (-5, 20),
    ])
    func bleibtInnerhalbDesErlaubtenBandes(given: Int, expected: Int) {
        #expect(TypingSpeed(wordsPerMinute: given).wordsPerMinute == expected)
    }

    @Test
    func teiltAuchBeiEinerGespeichertenNullNichtDurchNull() {
        #expect(TypingSpeed(wordsPerMinute: 0).time(forWords: 100).isFinite)
    }

    @Test(arguments: [
        (40, 40, 60.0),
        (40, 0, 0.0),
        (60, 90, 90.0),
        (130, 1300, 600.0),
    ])
    func rechnetWörterInTippzeitUm(wordsPerMinute: Int, words: Int, expected: TimeInterval) {
        let speed = TypingSpeed(wordsPerMinute: wordsPerMinute)
        #expect(abs(speed.time(forWords: words) - expected) < 0.001)
    }
}

struct SavedTimeTests {
    @Test(arguments: [
        // 90 words at 40 WPM cost 135 s of typing; 30 s of speech saves 105.
        (90, 30.0, 40, 105.0),
        // Speaking slower than typing saves nothing rather than losing time.
        (10, 60.0, 40, 0.0),
        (0, 0.0, 40, 0.0),
        // The same words save less against a faster typist.
        (90, 30.0, 60, 60.0),
    ])
    func istTippzeitMinusSprechzeit(
        words: Int,
        spokenSeconds: TimeInterval,
        wordsPerMinute: Int,
        expected: TimeInterval
    ) {
        let saved = SavedTime(
            words: words,
            spokenSeconds: spokenSeconds,
            typingAt: TypingSpeed(wordsPerMinute: wordsPerMinute)
        )
        #expect(abs(saved.seconds - expected) < 0.001)
    }

    @Test(arguments: [
        (0.0, "—"),
        (0.4, "—"),
        (1.0, "< 1min"),
        (59.0, "< 1min"),
        (60.0, "1min"),
        (750.0, "12min"),
        (3540.0, "59min"),
        (3600.0, "1:00h"),
        (3900.0, "1:05h"),
        (86_400.0, "24:00h"),
    ])
    func liestSichAlsMinutenBisZurVollenStunde(seconds: TimeInterval, expected: String) {
        // Built through the initialiser rather than by hand, so the label is
        // tested on values the formula can actually produce.
        let saved = SavedTime(words: 0, spokenSeconds: -seconds, typingAt: .default)
        #expect(saved.label == expected)
    }
}
