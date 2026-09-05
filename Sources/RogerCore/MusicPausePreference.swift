import Foundation

/// Whether Roger pauses whatever is playing for the duration of a dictation.
///
/// `@unchecked Sendable`: `UserDefaults` is thread-safe but not annotated as such.
public struct MusicPausePreference: @unchecked Sendable {
    private static let key = "com.mbr.roger.pausesMusicWhileDictating"

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Off by default: reaching into other apps' playback is not something to
    /// start doing unasked.
    public var pausesMusic: Bool {
        defaults.bool(forKey: Self.key)
    }

    public func store(_ pausesMusic: Bool) {
        defaults.set(pausesMusic, forKey: Self.key)
    }
}
