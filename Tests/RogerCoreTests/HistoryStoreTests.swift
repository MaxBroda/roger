import Foundation
import Testing

@testable import RogerCore

@MainActor
struct HistoryStoreTests {
    /// A Friday, so the week around it runs Monday 14 to Sunday 20 September.
    private let now = DateComponents(
        calendar: .current,
        year: 2026,
        month: 9,
        day: 18,
        hour: 12
    ).date!

    private func temporaryFile() -> URL {
        FileManager.default.temporaryDirectory.appending(path: "history-\(UUID().uuidString).json")
    }

    /// Ten words, so a short duration leaves a saving worth asserting on.
    private let tenWords = "eins zwei drei vier fünf sechs sieben acht neun zehn"

    private func archive(_ entries: [(recordedAt: String, duration: String)]) -> String {
        let records = entries.map { entry in
            """
            {
              "corrections" : [],
              \(entry.duration)
              "id" : "\(UUID().uuidString)",
              "recordedAt" : "\(entry.recordedAt)",
              "text" : "\(tenWords)"
            }
            """
        }
        return "{ \"lifetimeWords\" : 40, \"records\" : [\(records.joined(separator: ","))] }"
    }

    private func store(_ json: String) throws -> HistoryStore {
        let url = temporaryFile()
        try Data(json.utf8).write(to: url)
        return HistoryStore(fileURL: url)
    }

    private func outcome(_ text: String, duration: TimeInterval) -> DictationOutcome {
        DictationOutcome(
            raw: Transcript(text)!,
            polished: FormattingResult(transcript: Transcript(text)!),
            mode: .standard,
            duration: duration
        )
    }

    /// `duration` had to be optional: the store cannot tell a failed decode from
    /// a first launch, so a required field would drop the whole log in silence.
    @Test
    func lädtEinträgeAusDerZeitVorDerZeitmessung() throws {
        let store = try store(archive([(recordedAt: "2026-09-16T10:00:00Z", duration: "")]))

        #expect(store.records.count == 1)
        #expect(store.lifetimeWords == 40)
        #expect(store.records.first?.duration == nil)
    }

    @Test
    func zähltNurDieDiktateDerLaufendenWoche() throws {
        let store = try store(archive([
            (recordedAt: "2026-09-16T10:00:00Z", duration: "\"duration\" : 5,"),
            (recordedAt: "2026-09-10T10:00:00Z", duration: "\"duration\" : 5,"),
        ]))

        // Ten words at 40 WPM are 15 s of typing, 5 s of it spoken.
        #expect(abs(store.timeSavedThisWeek(typingAt: .default, now: now).seconds - 10) < 0.001)
    }

    @Test
    func nimmtDenMontagDieserWocheMitUndDenSonntagDavorNicht() throws {
        let store = try store(archive([
            (recordedAt: "2026-09-14T10:00:00Z", duration: "\"duration\" : 5,"),
            (recordedAt: "2026-09-13T10:00:00Z", duration: "\"duration\" : 5,"),
        ]))

        #expect(abs(store.timeSavedThisWeek(typingAt: .default, now: now).seconds - 10) < 0.001)
    }

    /// Counting their words at zero seconds would credit dictation with the full
    /// typing time of words it was never timed for; dropping them empties the
    /// readout for the whole week in which the update lands.
    @Test
    func schätztDieSprechzeitFürEinträgeOhneMessung() throws {
        let store = try store(archive([
            (recordedAt: "2026-09-16T10:00:00Z", duration: ""),
            (recordedAt: "2026-09-16T11:00:00Z", duration: "\"duration\" : 5,"),
        ]))

        // 20 words are 30 s of typing. Spoken: 5 s measured, plus 10 words
        // estimated at 130 WPM — 4,6 s.
        let estimated = TypingSpeed.spoken.time(forWords: 10)
        let saved = store.timeSavedThisWeek(typingAt: .default, now: now)
        #expect(abs(saved.seconds - (30 - 5 - estimated)) < 0.001)
    }

    /// The estimate only fills gaps — a measured entry keeps its own time.
    @Test
    func ziehtDerMessungDieSchätzungNichtVor() throws {
        let store = try store(archive([
            (recordedAt: "2026-09-16T10:00:00Z", duration: "\"duration\" : 5,"),
        ]))

        #expect(abs(store.timeSavedThisWeek(typingAt: .default, now: now).seconds - 10) < 0.001)
    }

    @Test
    func zeigtOhneDiktateDieserWocheNichts() throws {
        let store = try store(archive([(recordedAt: "2026-09-10T10:00:00Z", duration: "\"duration\" : 5,")]))

        #expect(store.timeSavedThisWeek(typingAt: .default, now: now).label == "—")
    }

    @Test
    func eineHöhereTippgeschwindigkeitSenktDieErsparnisRückwirkend() throws {
        let store = try store(archive([(recordedAt: "2026-09-16T10:00:00Z", duration: "\"duration\" : 5,")]))

        let slow = store.timeSavedThisWeek(typingAt: .default, now: now)
        let fast = store.timeSavedThisWeek(typingAt: TypingSpeed(wordsPerMinute: 80), now: now)

        #expect(slow.seconds > fast.seconds)
        // Ten words at 80 WPM are 7,5 s of typing, 5 s of it spoken.
        #expect(abs(fast.seconds - 2.5) < 0.001)
    }

    @Test
    func schreibtDieGemesseneDauerInDenEintrag() {
        let url = temporaryFile()
        defer { try? FileManager.default.removeItem(at: url) }
        let store = HistoryStore(fileURL: url)

        store.append(outcome("drei kleine Wörter", duration: 4.5))

        #expect(store.records.first?.duration == 4.5)
        #expect(store.lifetimeWords == 3)
        #expect(HistoryStore(fileURL: url).records.first?.duration == 4.5)
    }
}
