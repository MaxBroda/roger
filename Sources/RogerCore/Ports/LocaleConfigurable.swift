import Foundation

/// A transcriber whose language can be switched at runtime. Separate from
/// ``Transcribing`` because a multilingual model with auto-detection would have
/// nothing to say here.
public protocol LocaleConfigurable: Sendable {
    func activeLocale() async -> Locale
    func availableLocales() async -> [Locale]
    /// Languages whose model is already on the device.
    func installedLocales() async -> [Locale]
    /// Switches and downloads the model if needed.
    func use(_ locale: Locale) async throws
}
