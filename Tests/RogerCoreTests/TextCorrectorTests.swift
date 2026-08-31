import Foundation
import Testing

@testable import RogerCore

/// The correction pass is where a bug does silent damage: it rewrites text that
/// nobody compares against the original again.
struct TextCorrectorTests {
    private func corrector(_ entries: [(write: String, hear: String)]) -> TextCorrector {
        let dictionary = PhraseDictionary(
            entries: entries.compactMap { DictionaryEntry(written: $0.write, heard: $0.hear) }
        )
        return TextCorrector(rules: dictionary.rules)
    }

    @Test func ersetztDieVerhörform() {
        let result = corrector([("Claude Code", "cloud code")]).apply(to: "Ich starte cloud code.")
        #expect(result.text == "Ich starte Claude Code.")
        #expect(result.corrections == [AppliedCorrection(from: "cloud code", to: "Claude Code", count: 1)])
    }

    @Test func findetZusammengeschriebeneUndDurchgekoppelteFormen() {
        let subject = corrector([("Claude Code", "cloud code")])
        #expect(subject.apply(to: "CloudCode läuft").text == "Claude Code läuft")
        #expect(subject.apply(to: "Cloud-Code läuft").text == "Claude Code läuft")
        #expect(subject.apply(to: "cloud  code läuft").text == "Claude Code läuft")
    }

    /// The case it is all about: the rule may only fire on the *complete* pattern.
    @Test func lässtEchteWörterInRuhe() {
        let subject = corrector([("Claude Code", "cloud code")])
        #expect(subject.apply(to: "Cloudflare ist ein CDN").text == "Cloudflare ist ein CDN")
        #expect(subject.apply(to: "in der Cloud gespeichert").text == "in der Cloud gespeichert")
        #expect(subject.apply(to: "Cloudcodex").text == "Cloudcodex")
    }

    @Test func achtetAufWortgrenzen() {
        let subject = corrector([("Commit", "kommit")])
        #expect(subject.apply(to: "ein kommit").text == "ein Commit")
        #expect(subject.apply(to: "ein kommitment").text == "ein kommitment")
        #expect(subject.apply(to: "unkommit").text == "unkommit")
    }

    @Test func begriffStelltDieSchreibweiseRichtig() {
        let dictionary = PhraseDictionary(entries: [DictionaryEntry(written: "Claude Code")!])
        let subject = TextCorrector(rules: dictionary.rules)
        #expect(subject.apply(to: "mit claude code arbeiten").text == "mit Claude Code arbeiten")
        #expect(subject.apply(to: "mit CLAUDECODE arbeiten").text == "mit Claude Code arbeiten")
    }

    @Test func meldetNurEchteÄnderungen() {
        let dictionary = PhraseDictionary(entries: [DictionaryEntry(written: "Claude Code")!])
        let result = TextCorrector(rules: dictionary.rules).apply(to: "Claude Code läuft")
        #expect(result.text == "Claude Code läuft")
        #expect(result.corrections.isEmpty)
    }

    @Test func längstesMusterGewinnt() {
        let subject = corrector([
            ("Pull Request", "pull rikwest"),
            ("Request", "rikwest"),
        ])
        #expect(subject.apply(to: "ein pull rikwest").text == "ein Pull Request")
    }

    @Test func ersetzterTextWirdNichtErneutAngefasst() {
        // `Code` as its own term must not touch the `Code` that `Claude Code`
        // just produced.
        let dictionary = PhraseDictionary(entries: [
            DictionaryEntry(written: "Claude Code", heard: "cloud code")!,
            DictionaryEntry(written: "CODE")!,
        ])
        let result = TextCorrector(rules: dictionary.rules).apply(to: "cloud code")
        #expect(result.text == "Claude Code")
    }

    @Test func zähltMehrfachtreffer() {
        let result = corrector([("Claude Code", "cloud code")])
            .apply(to: "cloud code und cloud code")
        #expect(result.corrections == [AppliedCorrection(from: "cloud code", to: "Claude Code", count: 2)])
    }

    @Test func lässtTextOhneRegelnUnberührt() {
        let subject = TextCorrector(rules: [])
        #expect(subject.apply(to: "Nichts zu tun.").text == "Nichts zu tun.")
    }
}

struct DictionaryEntryTests {
    @Test func verwirftReineSchreibweisenPaare() {
        // `Pull Requests` already covers this as a term.
        #expect(DictionaryEntry(written: "Pull Requests", heard: "pull requests") == nil)
    }

    @Test func erlaubtAbweichendeWortzahl() {
        // A single-word term never finds the split form — a real pair.
        #expect(DictionaryEntry(written: "Raycast", heard: "ray cast") != nil)
    }

    @Test func warntVorGewöhnlichenWörtern() {
        let entry = DictionaryEntry(written: "Claude", heard: "cloud")!
        #expect(entry.risks == [.commonWord("cloud")])
    }

    @Test func warntVorSehrKurzenVerhörformen() {
        let entry = DictionaryEntry(written: "Pull Request", heard: "pr")!
        #expect(entry.risks == [.tooShort("pr")])
    }

    @Test func begriffeMitAbkürzungWarnenNicht() {
        #expect(DictionaryEntry(written: "API")!.risks.isEmpty)
        #expect(DictionaryEntry(written: "Claude Code")!.risks.isEmpty)
    }
}

struct PhraseDictionaryTests {
    @Test func hältMusterEindeutig() {
        var dictionary = PhraseDictionary()
        dictionary.upsert(DictionaryEntry(written: "Claude Code", heard: "cloud code")!)
        dictionary.upsert(DictionaryEntry(written: "Claude", heard: "cloud code")!)
        #expect(dictionary.entries.count == 1)
        #expect(dictionary.entries[0].written.text == "Claude")
    }

    @Test func kontextlisteBleibtKurzUndStelltMehrteiligeVoran() {
        let dictionary = PhraseDictionary(entries: DictionarySeed.entries)
        let phrases = dictionary.biasPhrases(limit: 10)
        #expect(phrases.count == 10)
        // Multi-word means more than one word in `Phrase` terms — hyphens split
        // there too, so `Merge-Konflikt` counts as two.
        #expect(phrases.allSatisfy { (Phrase($0)?.words.count ?? 0) > 1 })
    }

    @Test func dasBeispielwörterbuchIstInSichSauber() {
        let entries = DictionarySeed.entries
        // No entry gets lost when the invariants are checked.
        #expect(entries.count == DictionarySeed.terms.count + DictionarySeed.corrections.count)
        // And none displaces another.
        #expect(PhraseDictionary(entries: entries).entries.count == entries.count)
    }
}

/// The dictionary file is a promise: it should be editable in a text editor.
/// These tests pin down what that means.
struct DictionaryFileTests {
    private func decode(_ json: String) throws -> [DictionaryEntry] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode([DictionaryEntry].self, from: Data(json.utf8))
    }

    @Test func einMinimalerEintragGenügt() throws {
        let entries = try decode(#"[{"written": "Vercel"}]"#)
        #expect(entries.count == 1)
        #expect(entries[0].written.text == "Vercel")
        #expect(entries[0].kind == .term)
        #expect(entries[0].isEnabled)
    }

    @Test func korrekturpaarVonHand() throws {
        let entries = try decode(#"[{"written": "Claude Code", "heard": "cloud code"}]"#)
        #expect(entries[0].kind == .correction)
        #expect(entries[0].heard?.text == "cloud code")
    }

    @Test func schreibtSichAlsFlacheZeichenketten() throws {
        let entry = DictionaryEntry(written: "Claude Code", heard: "cloud code")!
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let json = String(decoding: try encoder.encode([entry]), as: UTF8.self)
        #expect(json.contains(#""written":"Claude Code""#))
        #expect(json.contains(#""heard":"cloud code""#))
    }

    @Test func begriffeSchreibenKeinLeeresGehört() throws {
        let entry = DictionaryEntry(written: "Vercel")!
        let json = String(decoding: try JSONEncoder().encode([entry]), as: UTF8.self)
        #expect(!json.contains("heard"))
    }
}
