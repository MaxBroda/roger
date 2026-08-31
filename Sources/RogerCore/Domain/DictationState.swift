import Foundation

/// Fixed order: `idle → recording → transcribing → injecting → idle`.
public enum DictationState: Equatable, Sendable {
    case idle
    case recording
    case transcribing
    case injecting
    case failed(String)

    /// Only idle admits a new recording.
    public var acceptsNewDictation: Bool { self == .idle }
}
