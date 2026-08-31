import Foundation

public enum RogerError: Error, LocalizedError {
    case microphonePermissionDenied
    case accessibilityPermissionDenied
    case transcriberUnavailable(locale: String)
    case audioEngineUnavailable(reason: String)
    case injectionFailed(reason: String)
    case hotkeyTapUnavailable

    public var errorDescription: String? {
        switch self {
        case .microphonePermissionDenied:
            "Kein Mikrofonzugriff. Systemeinstellungen → Datenschutz & Sicherheit → Mikrofon."
        case .accessibilityPermissionDenied:
            "Keine Bedienungshilfen-Berechtigung. Ohne sie kann Roger keinen Text einfügen."
        case .transcriberUnavailable(let locale):
            "Für die Sprache \(locale) ist keine Spracherkennung verfügbar."
        case .audioEngineUnavailable(let reason):
            "Audioaufnahme fehlgeschlagen: \(reason)"
        case .injectionFailed(let reason):
            "Text konnte nicht eingefügt werden: \(reason)"
        case .hotkeyTapUnavailable:
            "Tastatur-Tap konnte nicht erstellt werden. Fehlt die Eingabeüberwachung?"
        }
    }
}
