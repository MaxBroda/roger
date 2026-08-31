import Foundation
import RogerCore
import Speech

/// Diagnostics for the question "why doesn't Roger understand me?".
func line(_ label: String, _ value: some CustomStringConvertible) {
    print("  \(label.padding(toLength: 26, withPad: " ", startingAt: 0)) \(value)")
}

print("\nBerechtigungen  (die dieses Diagnose-Binarys, nicht die von Roger.app —\n                TCC entscheidet pro Bundle und Signatur)")
let permissions = await MainActor.run { Permissions.snapshot() }
line("Mikrofon", permissions.microphone)
line("Bedienungshilfen", permissions.accessibility)
line("Eingabeüberwachung", "\(permissions.inputMonitoring)  (nicht vorausgesetzt)")
line("vollständig", permissions.isComplete)

print("\nSprachumgebung")
line("Locale.current", Locale.current.identifier)
line("preferredLanguages", Locale.preferredLanguages.prefix(3).joined(separator: ", "))
line("AppleLanguages (defaults)", UserDefaults.standard.stringArray(forKey: "AppleLanguages")?.prefix(3).joined(separator: ", ") ?? "—")

print("\nSpeechTranscriber")
line("isAvailable", SpeechTranscriber.isAvailable)

let supported = await SpeechTranscriber.supportedLocales
let installed = await SpeechTranscriber.installedLocales
line("unterstützt", "\(supported.count) Sprachen")
line("installiert", installed.isEmpty ? "—" : installed.map(\.identifier).joined(separator: ", "))

let reserved = await AssetInventory.reservedLocales
line("reserviert", reserved.isEmpty ? "—" : reserved.map(\.identifier).joined(separator: ", "))
line("max. reservierbar", AssetInventory.maximumReservedLocales)

print("\nAuflösung je Kandidat")
let candidates = [Locale.current.identifier, "de-DE", "de_DE", "en-US"]
for identifier in candidates {
    let locale = Locale(identifier: identifier)
    let resolved = await SpeechTranscriber.supportedLocale(equivalentTo: locale)
    let module = SpeechTranscriber(locale: resolved ?? locale, preset: .transcription)
    let status = await AssetInventory.status(forModules: [module])
    line(identifier, "→ \(resolved?.identifier ?? "NICHT UNTERSTÜTZT")  [\(status)]")
}

print("\nDeutsche Varianten unter den unterstützten Sprachen")
let german = supported.filter { $0.identifier.hasPrefix("de") }
print("  \(german.isEmpty ? "—" : german.map(\.identifier).joined(separator: ", "))\n")
