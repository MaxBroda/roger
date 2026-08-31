import AVFAudio

/// A slice of recorded audio. `@unchecked Sendable` because the buffer is only
/// read after creation and belongs solely to the receiver from the `yield` on —
/// Apple does the same with `AnalyzerInput`.
public struct AudioChunk: @unchecked Sendable {
    public let buffer: AVAudioPCMBuffer

    public init(_ buffer: AVAudioPCMBuffer) {
        self.buffer = buffer
    }
}
