import Foundation

/// The languages Roger offers. The backend speaks about thirty — a menu with
/// thirty entries is a list, not a choice.
public struct LanguageCatalog: Sendable {
    private let identifiers: [String]

    public init(_ identifiers: [String]) {
        self.identifiers = identifiers
    }

    private static let defaultsKey = "com.mbr.roger.languages"
    private static let builtIn = ["de_DE", "en_US"]

    /// Overridable through `UserDefaults`, for trying things out: language models
    /// cannot be uninstalled on macOS, so an unloaded language is the only way to
    /// see the download path again.
    ///
    ///     defaults write com.mbr.roger com.mbr.roger.languages -array de_DE en_US fr_FR
    ///     defaults delete com.mbr.roger com.mbr.roger.languages
    public static var `default`: LanguageCatalog {
        let configured = UserDefaults.standard.stringArray(forKey: defaultsKey)
        return LanguageCatalog(configured?.isEmpty == false ? configured! : builtIn)
    }

    public var locales: [Locale] {
        identifiers.map(Locale.init(identifier:))
    }

    /// Intersection of catalogue and backend. The order comes from the catalogue —
    /// it is a decision, not an accident.
    public func filter(_ supported: [Locale]) -> [Locale] {
        locales.compactMap { wanted in
            supported.first { $0.matches(wanted) }
        }
    }

    public func contains(_ locale: Locale) -> Bool {
        locales.contains { $0.matches(locale) }
    }
}
