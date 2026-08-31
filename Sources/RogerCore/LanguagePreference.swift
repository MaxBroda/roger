import Foundation

/// Remembers the dictation language across launches. An explicit choice, because
/// `Locale.current` is the interface language, not the spoken one.
///
/// `@unchecked Sendable`: `UserDefaults` is thread-safe but not annotated as such.
public struct LanguagePreference: @unchecked Sendable {
    private static let key = "com.mbr.roger.dictationLocale"

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public var stored: Locale? {
        defaults.string(forKey: Self.key).map(Locale.init(identifier:))
    }

    public func store(_ locale: Locale) {
        defaults.set(locale.identifier, forKey: Self.key)
    }

    /// On first launch, the first system language the backend speaks.
    /// `Locale.preferredLanguages` rather than `Locale.current`: the latter falls
    /// back to English in a bundle without localisations.
    public func resolve(against supported: [Locale]) -> Locale? {
        if let stored, supported.contains(where: { $0.matches(stored) }) {
            return stored
        }
        for identifier in Locale.preferredLanguages {
            let candidate = Locale(identifier: identifier)
            if let match = supported.first(where: { $0.matches(candidate) }) {
                return match
            }
        }
        return supported.first
    }
}

extension Locale {
    /// Language *and* region, independent of spelling (`de-DE` vs. `de_DE`) and
    /// of suffixes (`en_US@rg=dezzzz`).
    public func matches(_ other: Locale) -> Bool {
        guard language.languageCode == other.language.languageCode else { return false }
        guard let lhs = region, let rhs = other.region else { return true }
        return lhs == rhs
    }

    /// In the language itself — "Deutsch (Deutschland)", not "German (Germany)".
    public var nativeDisplayName: String {
        localizedString(forIdentifier: identifier) ?? identifier
    }
}
