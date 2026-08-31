import AVFAudio
import Foundation

/// Microphone capture via `AVAudioEngine`, with format conversion: the interface
/// usually delivers 48 kHz stereo, the models want 16 kHz mono.
public final class MicrophoneCapture: AudioCapturing, @unchecked Sendable {
    private let engine = AVAudioEngine()
    private let lock = NSLock()
    private var continuation: AsyncStream<AudioChunk>.Continuation?

    public init() {}

    public func start(outputFormat: AVAudioFormat) throws -> AsyncStream<AudioChunk> {
        stop()

        let input = engine.inputNode
        let inputFormat = input.outputFormat(forBus: 0)
        guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0 else {
            throw RogerError.audioEngineUnavailable(reason: "Kein Eingabegerät verfügbar.")
        }

        let converter: AVAudioConverter?
        if inputFormat == outputFormat {
            converter = nil
        } else {
            guard let made = AVAudioConverter(from: inputFormat, to: outputFormat) else {
                throw RogerError.audioEngineUnavailable(
                    reason: "Format \(inputFormat) lässt sich nicht nach \(outputFormat) wandeln."
                )
            }
            converter = made
        }

        let (stream, continuation) = AsyncStream<AudioChunk>.makeStream(
            bufferingPolicy: .unbounded
        )
        lock.withLock { self.continuation = continuation }

        // 1024 frames at 48 kHz is about fifty readings per second; with 4096 the
        // display ran at twelve frames and felt sluggish.
        input.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { buffer, _ in
            guard let chunk = Self.prepare(buffer, converter: converter, outputFormat: outputFormat) else {
                return
            }
            continuation.yield(AudioChunk(chunk))
        }

        engine.prepare()
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            continuation.finish()
            lock.withLock { self.continuation = nil }
            throw RogerError.audioEngineUnavailable(reason: error.localizedDescription)
        }

        return stream
    }

    public func stop() {
        if engine.isRunning {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
        }
        let continuation = lock.withLock {
            let current = self.continuation
            self.continuation = nil
            return current
        }
        continuation?.finish()
    }

    private static func prepare(
        _ buffer: AVAudioPCMBuffer,
        converter: AVAudioConverter?,
        outputFormat: AVAudioFormat
    ) -> AVAudioPCMBuffer? {
        guard let converter else { return buffer }

        let ratio = outputFormat.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 1024
        guard let output = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: capacity) else {
            return nil
        }

        var conversionError: NSError?
        let source = SingleBufferSource(buffer)
        let status = converter.convert(to: output, error: &conversionError) { _, outStatus in
            guard let next = source.take() else {
                outStatus.pointee = .noDataNow
                return nil
            }
            outStatus.pointee = .haveData
            return next
        }

        guard status != .error, output.frameLength > 0 else { return nil }
        return output
    }
}

/// Yields exactly one buffer and nothing after — the contract `AVAudioConverter`
/// expects from its input block. `@unchecked Sendable` because the block runs
/// synchronously inside `convert(to:)` on the same thread.
private final class SingleBufferSource: @unchecked Sendable {
    private var buffer: AVAudioPCMBuffer?

    init(_ buffer: AVAudioPCMBuffer) {
        self.buffer = buffer
    }

    func take() -> AVAudioPCMBuffer? {
        defer { buffer = nil }
        return buffer
    }
}
