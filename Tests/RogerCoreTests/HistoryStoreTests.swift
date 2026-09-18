import Foundation
import Testing

@testable import RogerCore

@MainActor
struct HistoryStoreTests {
    /// The store reads `Calendar.current`, so the fixtures are built from it as
    /// well rather than from fixed UTC strings — otherwise the week boundary
    /// they describe moves with the machine's time zone and the test asserts
    /// something different in Auckland than in Berlin.
    private var calendar: Calendar {
        var calendar = Calendar.current
        calendar.firstWeekday = 2
        return calendar
    }

    /// A Friday noon, so the week around it has room on both sides.
    private var now: Date {
        DateComponents(calendar: calendar, year: 2026, month: 9, day: 18, hour: 12).date!
    }

    private var monday: Date { calendar.dateInterval(of: .weekOfYear, for: now)!.start }
    private var wednesday: Date { monday.addingTimeInterval(2 * 24 * 3600 + 10 * 3600) }
    private var lastSunday: Date { monday.addingTimeInterval(-3600) }
    private var nextMonday: Date { monday.addingTimeInterval(7 * 24 * 3600) }

    /// Ten words, so a short duration leaves a saving worth asserting on.
    private let tenWords = "eins zwei drei vier fünf sechs sieben acht neun zehn"

    private func temporaryFile() -> URL {
        FileManager.default.temporaryDirectory.appending(path: "history-\(UUID().uuidString).json")
    }

    private func archive(_ entries: [(at: Date, duration: TimeInterval?)]) -> String {
        let formatter = ISO8601DateFormatter()
        let records = entries.map { entry in
            """
            {
              "corrections" : [],
              \(entry.duration.map { "\"duration\" : \($0)," } ?? "")
              "id" : "\(UUID().uuidString)",
              "recordedAt" : "\(formatter.string(from: entry.at))",
              "text" : "\(tenWords)"
            }
            """
        }
        return "{ \"lifetimeWords\" : 40, \"records\" : [\(records.joined(separator: ","))] }"
    }

    private func store(_ entries: [(at: Date, duration: TimeInterval?)]) throws -> HistoryStore {
        let url = temporaryFile()
        try Data(archive(entries).utf8).write(to: url)
        return HistoryStore(fileURL: url, now: now)
    }

    private func outcome(_ text: String, duration: TimeInterval) -> DictationOutcome {
        DictationOutcome(
            raw: Transcript(text)!,
            polished: FormattingResult(transcript: Transcript(text)!),
            mode: .standard,
            duration: duration
        )
    }

    private func saving(_ store: HistoryStore, at date: Date? = nil) -> TimeInterval {
        store.timeSavedThisWeek(typingAt: .default, now: date ?? now).seconds
    }

    /// `duration` had to be optional: the store cannot tell a failed decode from
    /// a first launch, so a required field would drop the whole log in silence.
    @Test
    func lädtEinträgeAusDerZeitVorDerZeitmessung() throws {
        let store = try store([(at: wednesday, duration: nil)])

        #expect(store.records.count == 1)
        #expect(store.lifetimeWords == 40)
        #expect(store.records.first?.duration == nil)
    }

    @Test
    func zähltNurDieDiktateDerLaufendenWoche() throws {
        let store = try store([
            (at: wednesday, duration: 5),
            (at: monday.addingTimeInterval(-6 * 24 * 3600), duration: 5),
        ])

        // Ten words at 40 WPM are 15 s of typing, 5 s of it spoken.
        #expect(abs(saving(store) - 10) < 0.001)
    }

    @Test
    func nimmtDenMontagDieserWocheMitUndDenSonntagDavorNicht() throws {
        let store = try store([
            (at: monday, duration: 5),
            (at: lastSunday, duration: 5),
        ])

        #expect(abs(saving(store) - 10) < 0.001)
    }

    /// Counting their words at zero seconds would credit dictation with the full
    /// typing time of words it was never timed for; dropping them empties the
    /// readout for the whole week in which the update lands.
    @Test
    func schätztDieSprechzeitFürEinträgeOhneMessung() throws {
        let store = try store([
            (at: wednesday, duration: nil),
            (at: wednesday, duration: 5),
        ])

        // 20 words are 30 s of typing. Spoken: 5 s measured, plus 10 words
        // estimated at 130 WPM.
        #expect(abs(saving(store) - (30 - 5 - TypingSpeed.spoken.time(forWords: 10))) < 0.001)
    }

    /// The estimate only fills gaps — a measured entry keeps its own time.
    @Test
    func ziehtDerMessungDieSchätzungNichtVor() throws {
        let store = try store([(at: wednesday, duration: 5)])

        #expect(abs(saving(store) - 10) < 0.001)
    }

    @Test
    func zeigtOhneDiktateDieserWocheNichts() throws {
        let store = try store([(at: lastSunday, duration: 5)])

        #expect(store.timeSavedThisWeek(typingAt: .default, now: now).label == "—")
    }

    @Test
    func eineHöhereTippgeschwindigkeitSenktDieErsparnisRückwirkend() throws {
        let store = try store([(at: wednesday, duration: 5)])

        let fast = store.timeSavedThisWeek(typingAt: TypingSpeed(wordsPerMinute: 80), now: now)

        #expect(saving(store) > fast.seconds)
        // Ten words at 80 WPM are 7,5 s of typing, 5 s of it spoken.
        #expect(abs(fast.seconds - 2.5) < 0.001)
    }

    /// The log holds 500 entries; a week can hold more. Counting from the
    /// retained records alone would make a heavy week shrink as it goes on.
    @Test
    func überlebtDasVerdrängenAlterEinträgeDerselbenWoche() {
        let url = temporaryFile()
        defer { try? FileManager.default.removeItem(at: url) }
        // A small cap rather than the real 500: the eviction path is the point,
        // and every append rewrites the whole file — 500 of them make this test
        // slow enough to starve the other @MainActor suites running alongside it.
        let store = HistoryStore(fileURL: url, now: now, limit: 5)

        for _ in 1...8 { store.append(outcome("drei kleine Wörter", duration: 1)) }

        #expect(store.records.count == 5)
        // All 8 still count: 24 words are 36 s of typing, 8 s spoken.
        #expect(abs(saving(store, at: Date()) - (36 - 8)) < 0.001)
    }

    /// The tally is only rewritten by the next dictation, so until then it
    /// describes a week that is over.
    @Test
    func fälltZumWochenwechselAufNullZurück() throws {
        let store = try store([(at: wednesday, duration: 5)])

        #expect(abs(saving(store) - 10) < 0.001)
        #expect(store.timeSavedThisWeek(typingAt: .default, now: nextMonday).label == "—")
    }

    @Test
    func beginntInDerNeuenWocheBeiNull() {
        let url = temporaryFile()
        defer { try? FileManager.default.removeItem(at: url) }
        let store = HistoryStore(fileURL: url, now: now)
        store.append(outcome("drei kleine Wörter", duration: 1))

        let reopened = HistoryStore(fileURL: url, now: nextMonday)

        #expect(reopened.timeSavedThisWeek(typingAt: .default, now: nextMonday).label == "—")
        #expect(reopened.lifetimeWords == 3)
    }

    @Test
    func schreibtDieGemesseneDauerInDenEintrag() {
        let url = temporaryFile()
        defer { try? FileManager.default.removeItem(at: url) }
        let store = HistoryStore(fileURL: url, now: now)

        store.append(outcome("drei kleine Wörter", duration: 4.5))

        #expect(store.records.first?.duration == 4.5)
        #expect(store.lifetimeWords == 3)
        #expect(HistoryStore(fileURL: url, now: now).records.first?.duration == 4.5)
    }
}
