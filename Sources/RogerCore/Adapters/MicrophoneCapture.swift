import AVFoundation
import Foundation
import os

/// Microphone capture via `AVCaptureSession`.
///
/// Not `AVAudioEngine`: its AUHAL input gets no audio out of a Bluetooth headset.
/// The HFP link comes up, carries zero SCO packets and macOS tears it down after
/// about three seconds — with a pinned device and with the headset as the system
/// default alike. The capture stack drives the same headset for minutes.
///
/// It fits the job better in two more ways: the device choice is a plain
/// `AVCaptureDevice` looked up by the UID the preference persists, so no
/// AudioUnit has to be re-pointed behind the framework's back, and
/// `audioSettings` asks for the transcriber's format directly — the usual
/// 16 kHz mono arrives without a conversion step. The converter below is only
/// the fallback for a device that refuses those settings.
public final class MicrophoneCapture: NSObject, AudioCapturing, @unchecked Sendable {
    private static let log = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.mbr.roger",
        category: "audio"
    )

    private let preference: InputDevicePreference
    private let sampleQueue = DispatchQueue(label: "com.mbr.roger.audio.samples")
    private let lock = NSLock()

    private var session: AVCaptureSession?
    private var runtimeErrorObserver: NSObjectProtocol?
    private var continuation: AsyncStream<AudioChunk>.Continuation?
    private var targetFormat: AVAudioFormat?
    private var startedAt: ContinuousClock.Instant?
    private var firstBufferSeen = false
    private var bufferCount: UInt64 = 0

    /// Cached converter for the current input→output format pair. `AVAudioConverter`
    /// costs a few ms to build and would be called for every buffer, so it is
    /// rebuilt only when the delivered format actually shifts.
    private let converterLock = NSLock()
    private var cachedConverter: AVAudioConverter?
    private var cachedInputFormat: AVAudioFormat?

    public init(preference: InputDevicePreference = InputDevicePreference()) {
        self.preference = preference
        super.init()
        let allDevices = AudioDeviceEnumerator.inputDevices()
            .map { "\($0.name) [\($0.transport)]" }
            .joined(separator: ", ")
        Self.log.info("MicrophoneCapture initialised. available=[\(allDevices, privacy: .public)]")
    }

    deinit {
        if let runtimeErrorObserver {
            NotificationCenter.default.removeObserver(runtimeErrorObserver)
        }
    }

    public func start(outputFormat: AVAudioFormat) throws -> AsyncStream<AudioChunk> {
        stop()

        let selection = preference.selection
        Self.log.info("start() preference=\(String(describing: selection), privacy: .public)")

        let device = try captureDevice(for: selection)
        let session = try makeSession(device: device, outputFormat: outputFormat)

        let (stream, continuation) = AsyncStream<AudioChunk>.makeStream(
            bufferingPolicy: .unbounded
        )
        let startInstant = ContinuousClock.now
        lock.withLock {
            self.session = session
            self.continuation = continuation
            self.targetFormat = outputFormat
            self.startedAt = startInstant
            self.firstBufferSeen = false
            self.bufferCount = 0
        }
        converterLock.withLock {
            self.cachedConverter = nil
            self.cachedInputFormat = nil
        }
        observeRuntimeErrors(on: session)

        session.startRunning()
        guard session.isRunning else {
            Self.log.error("capture session did not start.")
            stop()
            throw RogerError.audioEngineUnavailable(reason: "Aufnahme konnte nicht gestartet werden.")
        }
        Self.log.info(
            "capturing from \(device.localizedName, privacy: .public) [uid=\(device.uniqueID, privacy: .public)] outputFormat=\(Self.describeFormat(outputFormat), privacy: .public)"
        )

        return stream
    }

    public func stop() {
        let (session, continuation, observer, buffers, duration) = lock.withLock {
            () -> (AVCaptureSession?, AsyncStream<AudioChunk>.Continuation?, NSObjectProtocol?, UInt64, Duration?) in
            let result = (
                self.session,
                self.continuation,
                self.runtimeErrorObserver,
                self.bufferCount,
                self.startedAt.map { ContinuousClock.now - $0 }
            )
            self.session = nil
            self.continuation = nil
            self.runtimeErrorObserver = nil
            self.targetFormat = nil
            self.startedAt = nil
            self.firstBufferSeen = false
            self.bufferCount = 0
            return result
        }
        converterLock.withLock {
            self.cachedConverter = nil
            self.cachedInputFormat = nil
        }
        if let observer {
            NotificationCenter.default.removeObserver(observer)
        }
        // Tearing the session down releases the device: a Bluetooth headset
        // stays in low-quality HFP mode as long as anyone holds its input.
        if let session {
            if session.isRunning {
                session.stopRunning()
            }
            let durationText = duration.map { "\($0)" } ?? "—"
            Self.log.info("stop() completed. buffers=\(buffers, privacy: .public) sessionDuration=\(durationText, privacy: .public)")
        }
        continuation?.finish()
    }

    // MARK: - Session setup

    /// The capture device behind the user's choice. `AVCaptureDevice.uniqueID`
    /// is CoreAudio's device UID, the very string the preference persists, so
    /// both identify the same device without a lookup table.
    private func captureDevice(for selection: InputDeviceSelection) throws -> AVCaptureDevice {
        if let device = AudioDeviceEnumerator.resolve(selection),
           let capture = AVCaptureDevice(uniqueID: device.uid) {
            return capture
        }
        Self.log.notice(
            "preferred input device not available for selection \(String(describing: selection), privacy: .public) — falling back to system default."
        )
        guard let fallback = AVCaptureDevice.default(for: .audio) else {
            throw RogerError.audioEngineUnavailable(reason: "Kein Eingabegerät verfügbar.")
        }
        return fallback
    }

    private func makeSession(device: AVCaptureDevice, outputFormat: AVAudioFormat) throws -> AVCaptureSession {
        let session = AVCaptureSession()
        session.beginConfiguration()

        let input: AVCaptureDeviceInput
        do {
            input = try AVCaptureDeviceInput(device: device)
        } catch {
            session.commitConfiguration()
            Self.log.error("cannot open \(device.localizedName, privacy: .public): \(error.localizedDescription, privacy: .public)")
            throw RogerError.audioEngineUnavailable(reason: error.localizedDescription)
        }
        guard session.canAddInput(input) else {
            session.commitConfiguration()
            throw RogerError.audioEngineUnavailable(reason: "Eingabegerät \(device.localizedName) ist belegt.")
        }
        session.addInput(input)

        let output = AVCaptureAudioDataOutput()
        output.audioSettings = Self.audioSettings(for: outputFormat)
        output.setSampleBufferDelegate(self, queue: sampleQueue)
        guard session.canAddOutput(output) else {
            session.commitConfiguration()
            throw RogerError.audioEngineUnavailable(reason: "Audioausgang konnte nicht eingerichtet werden.")
        }
        session.addOutput(output)

        session.commitConfiguration()
        return session
    }

    /// The format the capture stack should hand over. macOS honours this for
    /// audio outputs, so the buffers usually arrive ready for the transcriber.
    private static func audioSettings(for format: AVAudioFormat) -> [String: Any] {
        let asbd = format.streamDescription.pointee
        return [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: asbd.mSampleRate,
            AVNumberOfChannelsKey: asbd.mChannelsPerFrame,
            AVLinearPCMBitDepthKey: asbd.mBitsPerChannel,
            AVLinearPCMIsFloatKey: asbd.mFormatFlags & kAudioFormatFlagIsFloat != 0,
            AVLinearPCMIsBigEndianKey: asbd.mFormatFlags & kAudioFormatFlagIsBigEndian != 0,
            AVLinearPCMIsNonInterleaved: asbd.mFormatFlags & kAudioFormatFlagIsNonInterleaved != 0,
        ]
    }

    /// The session stops itself on a runtime error — an unplugged device, a
    /// Bluetooth link that dropped. The dictation cannot continue, so end the
    /// stream and let the caller's watchdog take over.
    private func observeRuntimeErrors(on session: AVCaptureSession) {
        let observer = NotificationCenter.default.addObserver(
            forName: AVCaptureSession.runtimeErrorNotification,
            object: session,
            queue: nil
        ) { [weak self] notification in
            guard let self else { return }
            let error = notification.userInfo?[AVCaptureSessionErrorKey] as? NSError
            Self.log.error("capture session runtime error: \(error?.localizedDescription ?? "unknown", privacy: .public)")
            self.stop()
        }
        lock.withLock { self.runtimeErrorObserver = observer }
    }

    // MARK: - Sample handling

    private func handle(_ sampleBuffer: CMSampleBuffer) {
        let (continuation, target) = lock.withLock { (self.continuation, self.targetFormat) }
        guard let continuation, let target else { return }
        guard let buffer = Self.pcmBuffer(from: sampleBuffer) else { return }

        recordArrival(buffer: buffer)

        guard !Self.formatsMatch(buffer.format, target) else {
            continuation.yield(AudioChunk(buffer))
            return
        }
        guard
            let converter = converter(for: buffer.format, target: target),
            let converted = Self.convert(buffer, converter: converter, outputFormat: target)
        else { return }
        continuation.yield(AudioChunk(converted))
    }

    private static func pcmBuffer(from sampleBuffer: CMSampleBuffer) -> AVAudioPCMBuffer? {
        guard
            let description = CMSampleBufferGetFormatDescription(sampleBuffer),
            let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(description),
            let format = AVAudioFormat(streamDescription: asbd)
        else { return nil }

        let frames = AVAudioFrameCount(CMSampleBufferGetNumSamples(sampleBuffer))
        guard frames > 0, let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) else {
            return nil
        }
        buffer.frameLength = frames
        let status = CMSampleBufferCopyPCMDataIntoAudioBufferList(
            sampleBuffer,
            at: 0,
            frameCount: Int32(frames),
            into: buffer.mutableAudioBufferList
        )
        guard status == noErr else {
            Self.log.error("copying sample data failed: OSStatus=\(status, privacy: .public)")
            return nil
        }
        return buffer
    }

    /// Compares what matters here: rate, channels, sample type, layout.
    /// `AVAudioFormat`'s own equality also weighs the channel layout object,
    /// which the capture stack fills in differently for the same mono stream.
    private static func formatsMatch(_ lhs: AVAudioFormat, _ rhs: AVAudioFormat) -> Bool {
        lhs.sampleRate == rhs.sampleRate
            && lhs.channelCount == rhs.channelCount
            && lhs.commonFormat == rhs.commonFormat
            && lhs.isInterleaved == rhs.isInterleaved
    }

    private func recordArrival(buffer: AVAudioPCMBuffer) {
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
                "first buffer received after \(latency, privacy: .public). frameLength=\(buffer.frameLength, privacy: .public) format=\(Self.describeFormat(buffer.format), privacy: .public)"
            )
        }
    }

    /// Returns a converter that turns `inputFormat` into `outputFormat`, reused
    /// across buffers of the same input format. `nil` if it cannot be built.
    private func converter(for inputFormat: AVAudioFormat, target outputFormat: AVAudioFormat) -> AVAudioConverter? {
        converterLock.withLock {
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

    private static func convert(
        _ buffer: AVAudioPCMBuffer,
        converter: AVAudioConverter,
        outputFormat: AVAudioFormat
    ) -> AVAudioPCMBuffer? {
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

    private static func describeFormat(_ format: AVAudioFormat) -> String {
        "\(Int(format.sampleRate))Hz/\(format.channelCount)ch/\(format.commonFormat.rawValue)"
    }
}

extension MicrophoneCapture: AVCaptureAudioDataOutputSampleBufferDelegate {
    public func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        handle(sampleBuffer)
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
