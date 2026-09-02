import AVFAudio
import CoreAudio
import Foundation
import os

/// Microphone capture via `AVAudioEngine`, with format conversion: the interface
/// usually delivers 48 kHz stereo, the models want 16 kHz mono.
///
/// The tap is installed with `format: nil`, so `AVAudioEngine` picks the current
/// hardware format on its own and adapts when it changes — e.g. when a Bluetooth
/// headset switches from A2DP playback (44.1/48 kHz stereo) to HFP (16 kHz mono)
/// the moment the mic becomes active. A pinned format would tear the tap down.
/// The converter follows: it is rebuilt whenever the buffer format differs from
/// the last one seen, so a mid-recording route change keeps producing chunks.
public final class MicrophoneCapture: AudioCapturing, @unchecked Sendable {
    private static let log = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.mbr.roger",
        category: "audio"
    )

    private var engine = AVAudioEngine()
    private let lock = NSLock()
    private var continuation: AsyncStream<AudioChunk>.Continuation?
    private var startedAt: ContinuousClock.Instant?
    private var firstBufferSeen = false
    private var bufferCount: UInt64 = 0
    private var configChangeObserver: NSObjectProtocol?
    /// Set when a configuration change fires between sessions. The engine then
    /// carries stale internal wiring and `engine.start()` reports -10868
    /// (format not supported) even though `outputFormat(forBus:)` still claims
    /// the old format. Rebuilding the engine on the next `start()` clears it.
    private var engineNeedsRebuild = false

    /// Cached converter for the current input→output format pair. `AVAudioConverter`
    /// costs a few ms to build and gets called for every 20 ms buffer, so rebuilding
    /// per callback is wasteful. Rebuilt only when the input format actually shifts.
    private let converterLock = NSLock()
    private var cachedConverter: AVAudioConverter?
    private var cachedInputFormat: AVAudioFormat?

    public init() {
        observeConfigurationChanges()
        Self.log.info("MicrophoneCapture initialised. defaultInput=\(Self.describeDefaultInputDevice(), privacy: .public)")
    }

    deinit {
        if let observer = configChangeObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    public func start(outputFormat: AVAudioFormat) throws -> AsyncStream<AudioChunk> {
        stop()

        // If a route change happened between sessions the engine's internal
        // wiring is stale — rebuild before querying anything on it.
        let shouldRebuild = lock.withLock {
            let value = engineNeedsRebuild
            engineNeedsRebuild = false
            return value
        }
        if shouldRebuild {
            Self.log.info("rebuilding AVAudioEngine before start(): stale after route change.")
            rebuildEngine()
        }

        let input = engine.inputNode
        let initialFormat = input.outputFormat(forBus: 0)
        Self.log.info(
            "start() requested. defaultInput=\(Self.describeDefaultInputDevice(), privacy: .public) initialInputFormat=\(Self.describeFormat(initialFormat), privacy: .public) outputFormat=\(Self.describeFormat(outputFormat), privacy: .public)"
        )
        guard initialFormat.sampleRate > 0, initialFormat.channelCount > 0 else {
            Self.log.error("start() aborted: input format has zero sample rate or channel count.")
            throw RogerError.audioEngineUnavailable(reason: "Kein Eingabegerät verfügbar.")
        }

        let (stream, continuation) = AsyncStream<AudioChunk>.makeStream(
            bufferingPolicy: .unbounded
        )
        let startInstant = ContinuousClock.now
        lock.withLock {
            self.continuation = continuation
            self.startedAt = startInstant
            self.firstBufferSeen = false
            self.bufferCount = 0
        }
        converterLock.withLock {
            self.cachedConverter = nil
            self.cachedInputFormat = nil
        }

        // 1024 frames at 48 kHz is about fifty readings per second; with 4096 the
        // display ran at twelve frames and felt sluggish.
        //
        // `format: nil` lets AVAudioEngine follow whatever the hardware currently
        // offers. Pinning a format here would raise NSInternalInconsistencyException
        // as soon as the route changes (Bluetooth A2DP→HFP, headphones plugging in).
        input.installTap(onBus: 0, bufferSize: 1024, format: nil) { [weak self] buffer, _ in
            guard let self else { return }
            self.recordTapCallback(buffer: buffer)
            let converter = self.converter(for: buffer.format, target: outputFormat)
            guard let chunk = Self.prepare(buffer, converter: converter, outputFormat: outputFormat) else {
                return
            }
            continuation.yield(AudioChunk(chunk))
        }

        engine.prepare()
        do {
            try engine.start()
            Self.log.info("engine started. isRunning=\(self.engine.isRunning, privacy: .public)")
        } catch {
            Self.log.error("engine.start() threw: \(error.localizedDescription, privacy: .public)")
            input.removeTap(onBus: 0)
            continuation.finish()
            lock.withLock {
                self.continuation = nil
                self.startedAt = nil
            }
            throw RogerError.audioEngineUnavailable(reason: error.localizedDescription)
        }

        return stream
    }

    public func stop() {
        let wasRunning = engine.isRunning
        if wasRunning {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
        }
        let (continuation, buffers, duration) = lock.withLock { () -> (AsyncStream<AudioChunk>.Continuation?, UInt64, Duration?) in
            let current = self.continuation
            let count = self.bufferCount
            let dur = self.startedAt.map { ContinuousClock.now - $0 }
            self.continuation = nil
            self.startedAt = nil
            self.firstBufferSeen = false
            self.bufferCount = 0
            return (current, count, dur)
        }
        converterLock.withLock {
            self.cachedConverter = nil
            self.cachedInputFormat = nil
        }
        // Rebuild the engine so the input node stops holding the mic device
        // open. `engine.stop()` alone leaves the HAL IOProc reserved, which
        // keeps Bluetooth headphones stuck in low-quality HFP mode until the
        // process exits.
        if wasRunning {
            rebuildEngine()
            Self.log.info("engine rebuilt after stop() to release the input device.")
        }
        if wasRunning || continuation != nil {
            let durationText = duration.map { "\($0)" } ?? "—"
            Self.log.info("stop() completed. buffers=\(buffers, privacy: .public) sessionDuration=\(durationText, privacy: .public)")
        }
        continuation?.finish()
    }

    /// Returns a converter that turns `inputFormat` into `outputFormat`. A single
    /// converter is reused across buffers of the same input format; when the
    /// format changes (route change) it is rebuilt on the next call.
    /// `nil` if the formats already match or the converter cannot be built.
    private func converter(for inputFormat: AVAudioFormat, target outputFormat: AVAudioFormat) -> AVAudioConverter? {
        if inputFormat == outputFormat { return nil }
        return converterLock.withLock {
            if let cached = cachedConverter, cachedInputFormat == inputFormat {
                return cached
            }
            let made = AVAudioConverter(from: inputFormat, to: outputFormat)
            if made == nil {
                Self.log.error("no AVAudioConverter for \(Self.describeFormat(inputFormat), privacy: .public) → \(Self.describeFormat(outputFormat), privacy: .public)")
            } else {
                Self.log.info("converter (re)built for \(Self.describeFormat(inputFormat), privacy: .public) → \(Self.describeFormat(outputFormat), privacy: .public)")
            }
            cachedConverter = made
            cachedInputFormat = inputFormat
            return made
        }
    }

    private func recordTapCallback(buffer: AVAudioPCMBuffer) {
        var latency: Duration?
        var isFirst = false
        lock.withLock {
            bufferCount += 1
            if !firstBufferSeen, let startedAt {
                firstBufferSeen = true
                isFirst = true
                latency = ContinuousClock.now - startedAt
            }
        }
        if isFirst, let latency {
            Self.log.info(
                "first tap buffer received after \(latency, privacy: .public). frameLength=\(buffer.frameLength, privacy: .public) format=\(Self.describeFormat(buffer.format), privacy: .public)"
            )
        }
    }

    /// Replaces the `AVAudioEngine` instance with a fresh one and re-registers
    /// the configuration-change observer on it. Called when a route change
    /// during idle left the engine in a stale internal state.
    private func rebuildEngine() {
        if let observer = configChangeObserver {
            NotificationCenter.default.removeObserver(observer)
            configChangeObserver = nil
        }
        engine = AVAudioEngine()
        observeConfigurationChanges()
    }

    /// Route-change handler as per Apple's AVAudioEngine guidance: the engine has
    /// stopped itself internally, so restart it. The tap survives because it was
    /// installed with `format: nil` and will pick up the new hardware format.
    private func observeConfigurationChanges() {
        configChangeObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: engine,
            queue: nil
        ) { [weak self] _ in
            guard let self else { return }
            let running = self.engine.isRunning
            let sinceStart = self.lock.withLock { self.startedAt.map { ContinuousClock.now - $0 } }
            let sinceText = sinceStart.map { "\($0)" } ?? "—"
            let hasActiveSession = self.lock.withLock { self.continuation != nil }
            let newFormat = self.engine.inputNode.outputFormat(forBus: 0)
            Self.log.notice(
                "AVAudioEngineConfigurationChange fired. engineRunning=\(running, privacy: .public) sinceStart=\(sinceText, privacy: .public) newDefaultInput=\(Self.describeDefaultInputDevice(), privacy: .public) newInputFormat=\(Self.describeFormat(newFormat), privacy: .public) hasActiveSession=\(hasActiveSession, privacy: .public)"
            )

            // Only restart if a dictation is actually in progress. Notifications
            // that arrive between sessions cannot be repaired by restarting —
            // `engine.start()` would report -10868 (format mismatch) because the
            // engine's cached AudioUnit wiring is stale. Mark it for rebuild
            // instead; the next `start()` will get a fresh engine.
            guard hasActiveSession else {
                self.lock.withLock { self.engineNeedsRebuild = true }
                return
            }

            // Restart on the engine's own thread would deadlock; hop off.
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                guard let self else { return }
                // Bail out if the session ended in the meantime.
                let stillActive = self.lock.withLock { self.continuation != nil }
                guard stillActive else { return }

                if self.engine.isRunning {
                    self.engine.stop()
                }
                do {
                    self.engine.prepare()
                    try self.engine.start()
                    Self.log.info("engine restarted after configuration change. isRunning=\(self.engine.isRunning, privacy: .public)")
                } catch {
                    Self.log.error("engine restart after configuration change failed: \(error.localizedDescription, privacy: .public)")
                    // Give up on this session, let the caller's watchdog handle it.
                    let continuation = self.lock.withLock { () -> AsyncStream<AudioChunk>.Continuation? in
                        let current = self.continuation
                        self.continuation = nil
                        self.startedAt = nil
                        return current
                    }
                    continuation?.finish()
                }
            }
        }
    }

    // MARK: - Diagnostics helpers

    private static func describeFormat(_ format: AVAudioFormat) -> String {
        "\(Int(format.sampleRate))Hz/\(format.channelCount)ch/\(format.commonFormat.rawValue)"
    }

    private static func describeDefaultInputDevice() -> String {
        var deviceID = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size,
            &deviceID
        )
        guard status == noErr, deviceID != 0 else {
            return "unknown(status=\(status))"
        }
        return "\(deviceName(for: deviceID)) [id=\(deviceID)]"
    }

    private static func deviceName(for deviceID: AudioDeviceID) -> String {
        var name: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<CFString?>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertyName,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let status = AudioObjectGetPropertyData(
            deviceID,
            &address,
            0,
            nil,
            &size,
            &name
        )
        guard status == noErr, let name else { return "unknown" }
        return name.takeRetainedValue() as String
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
