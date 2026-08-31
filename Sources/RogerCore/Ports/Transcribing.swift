import AVFAudio

/// Turns an audio stream into text. Swappable: on-device (Speech framework),
/// local model (Parakeet/Whisper) or cloud.
public protocol Transcribing: Sendable {
    /// Load models, reserve the locale, settle permissions. Once at launch.
    func prepare() async throws

    func preferredAudioFormat() async -> AVAudioFormat?

    /// Consumes audio until the stream ends. `nil` means nothing usable was spoken.
    func transcribe(_ audio: AsyncStream<AudioChunk>) async throws -> Transcript?
}
