import RogerCore

/// A table instead of `UCKeyTranslate`: translating through the keyboard layout
/// yields control codes for Esc, F5 or the arrow keys, not readable characters.
enum KeyNames {
    static func name(of keyCode: UInt16) -> String {
        table[keyCode] ?? "Taste \(keyCode)"
    }

    /// "Esc halten · 220 ms".
    static func description(of binding: HotkeyBinding) -> String {
        let milliseconds = Int(binding.holdThreshold.timeInterval * 1000)
        return "\(name(of: binding.keyCode)) halten · \(milliseconds) ms"
    }

    private static let table: [UInt16: String] = [
        53: "Esc",
        48: "Tab",
        36: "Return",
        49: "Leertaste",
        51: "Rückschritt",
        117: "Entf",
        114: "Hilfe",
        71: "Löschen (Ziffernblock)",
        76: "Enter (Ziffernblock)",

        123: "Pfeil links", 124: "Pfeil rechts", 125: "Pfeil ab", 126: "Pfeil auf",
        115: "Pos1", 119: "Ende", 116: "Bild auf", 121: "Bild ab",

        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6",
        98: "F7", 100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12",
        105: "F13", 107: "F14", 113: "F15", 106: "F16", 64: "F17", 79: "F18",
        80: "F19", 90: "F20",

        55: "Befehl links", 54: "Befehl rechts",
        56: "Umschalt links", 60: "Umschalt rechts",
        58: "Wahl links", 61: "Wahl rechts",
        59: "Strg links", 62: "Strg rechts",
        57: "Feststelltaste", 63: "Funktionstaste",
    ]
}
