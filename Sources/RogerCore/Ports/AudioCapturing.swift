import AVFAudio

/// Microphone capture. Delivers audio in the format the transcriber asks for.
public protocol AudioCapturing: Sendable {
    /// The stream ends once ``stop()`` is called.
    func start(outputFormat: AVAudioFormat) throws -> AsyncStream<AudioChunk>
    func stop()
}
