import AVFAudio
import Foundation
import os

/// The state machine. Knows no frameworks — only the five ports.
///
/// Key held → microphone on, audio streams into the transcriber. Released →
/// microphone off, the stream ends, the result gets formatted and injected.
@MainActor
public final class DictationSession {
    private static let log = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.mbr.roger",
        category: "session"
    )

    /// Ceilings so no state can hang — without them any backend stall is final and
    /// only a relaunch brings Roger back.
    private enum Limit {
        static let recording: Duration = .seconds(300)
        static let finishing: Duration = .seconds(30)
    }

    public private(set) var state: DictationState = .idle {
        didSet {
            guard state != oldValue else { return }
            armWatchdog()
            onStateChange?(state)
        }
    }

    public var onStateChange: (@MainActor (DictationState) -> Void)?

    /// Frequency bands of the running dictation, 0…1 each.
    public var onSpectrum: (@MainActor ([Float]) -> Void)?

    /// A finished dictation plus the dictionary's changes — the log hangs off this.
    public var onCompleted: (@MainActor (FormattingResult) -> Void)?

    private let hotkey: any HotkeyMonitoring
    private let audio: any AudioCapturing
    private let transcriber: any Transcribing
    private let formatter: any TextFormatting
    private let injector: any TextInjecting
    /// Passed in at construction rather than set later: the display drops band
    /// arrays of unexpected length, and forgetting to set it would be a silently
    /// dead meter.
    private let spectrumBandCount: Int

    private var dictationTask: Task<Void, Never>?
    private var watchdog: Task<Void, Never>?
    /// Counts dictations: this is how a straggler tells whether it still belongs
    /// to the dictation it was started for.
    private var generation = 0

    public init(
        hotkey: any HotkeyMonitoring,
        audio: any AudioCapturing,
        transcriber: any Transcribing,
        formatter: any TextFormatting,
        injector: any TextInjecting,
        spectrumBandCount: Int
    ) {
        self.hotkey = hotkey
        self.audio = audio
        self.transcriber = transcriber
        self.formatter = formatter
        self.injector = injector
        self.spectrumBandCount = spectrumBandCount
    }

    /// Runs until the hotkey stream ends. No `prepare()` here — that is the
    /// caller's; a second one reloaded the model and, on failure, left the event
    /// tap unset.
    public func run() async throws {
        for await event in try hotkey.start() {
            switch event {
            case .pressBegan: begin()
            case .pressEnded: end()
            }
        }
    }

    /// The button in the window: the same path as the key, just without holding.
    public func startDictation() {
        begin()
    }

    public func stopDictation() {
        end()
    }

    public func toggleDictation() {
        state == .recording ? end() : begin()
    }

    public func shutdown() {
        generation += 1
        watchdog?.cancel()
        watchdog = nil
        dictationTask?.cancel()
        audio.stop()
        hotkey.stop()
        state = .idle
    }

    private func begin() {
        guard state.acceptsNewDictation else { return }
        generation += 1
        let generation = self.generation
        state = .recording
        Self.log.info("begin() generation=\(generation, privacy: .public)")

        dictationTask = Task { [audio, transcriber, formatter, injector] in
            do {
                let beginInstant = ContinuousClock.now
                let format = await transcriber.preferredAudioFormat() ?? AudioFormat.fallback
                let formatElapsed = ContinuousClock.now - beginInstant
                Self.log.info("preferredAudioFormat resolved after \(formatElapsed, privacy: .public) generation=\(generation, privacy: .public)")

                // Released before the backend named its format: opening the
                // microphone now would hang the session in transcribing forever,
                // because the `stop()` from `end()` has already passed.
                guard self.generation == generation, self.state == .recording else {
                    Self.log.info("dictation cancelled before openMicrophone. generation=\(generation, privacy: .public)")
                    self.setState(.idle, generation: generation)
                    return
                }

                let openInstant = ContinuousClock.now
                let source = try await self.openMicrophone(audio, format: format)
                let openElapsed = ContinuousClock.now - openInstant
                Self.log.info("openMicrophone completed after \(openElapsed, privacy: .public) generation=\(generation, privacy: .public)")

                // Second check: if the release fell between opening and here, the
                // `stop()` ran into nothing.
                guard self.generation == generation, self.state == .recording else {
                    Self.log.info("dictation cancelled between open and transcribe. generation=\(generation, privacy: .public)")
                    self.closeMicrophone(audio)
                    self.setState(.idle, generation: generation)
                    return
                }

                let stream = self.metered(source, sampleRate: format.sampleRate)

                let transcribeInstant = ContinuousClock.now
                // Runs until `end()` stops the microphone and the stream ends.
                guard let raw = try await transcriber.transcribe(stream) else {
                    Self.log.info("transcribe returned nil. generation=\(generation, privacy: .public)")
                    self.setState(.idle, generation: generation)
                    return
                }
                let transcribeElapsed = ContinuousClock.now - transcribeInstant
                Self.log.info("transcribe completed after \(transcribeElapsed, privacy: .public) generation=\(generation, privacy: .public)")

                let polished = try await formatter.format(raw)

                // After a cancel the text would land in an app that is long gone.
                guard self.generation == generation else { return }

                self.state = .injecting
                try await injector.inject(polished.transcript)
                self.onCompleted?(polished)
                self.setState(.idle, generation: generation)
            } catch is CancellationError {
                Self.log.info("dictation cancelled via CancellationError. generation=\(generation, privacy: .public)")
                self.setState(.idle, generation: generation)
            } catch {
                Self.log.error("dictation failed: \(error.localizedDescription, privacy: .public) generation=\(generation, privacy: .public)")
                await self.fail(with: error, generation: generation)
            }
        }
    }

    /// Taps the display onto the audio stream without holding it up.
    private func metered(
        _ source: AsyncStream<AudioChunk>,
        sampleRate: Double
    ) -> AsyncStream<AudioChunk> {
        guard onSpectrum != nil,
              let analyzer = SpectrumAnalyzer(
                  bandCount: spectrumBandCount,
                  sampleRate: sampleRate
              )
        else { return source }

        let (stream, continuation) = AsyncStream<AudioChunk>.makeStream(
            bufferingPolicy: .unbounded
        )
        Task { [weak self] in
            for await chunk in source {
                continuation.yield(chunk)
                let bands = analyzer.analyze(chunk)
                self?.onSpectrum?(bands)
            }
            continuation.finish()
        }
        return stream
    }

    private func end() {
        guard state == .recording else { return }
        Self.log.info("end() generation=\(self.generation, privacy: .public)")
        state = .transcribing
        closeMicrophone(audio)
    }

    /// `nonisolated` on purpose: opening a capture device can block for seconds,
    /// and macOS revokes the event tap when the main thread stalls.
    private nonisolated func openMicrophone(
        _ audio: any AudioCapturing,
        format: AVAudioFormat
    ) async throws -> AsyncStream<AudioChunk> {
        try audio.start(outputFormat: format)
    }

    /// Off the main thread as well. The caller does not wait — the stream ends
    /// once the engine stops.
    private nonisolated func closeMicrophone(_ audio: any AudioCapturing) {
        Task.detached { audio.stop() }
    }

    private func fail(with error: any Error, generation: Int) async {
        setState(.failed(error.localizedDescription), generation: generation)
        try? await Task.sleep(for: .seconds(3))
        guard generation == self.generation, case .failed = state else { return }
        state = .idle
    }

    /// Only if the writer still belongs to the running dictation — otherwise a
    /// cancelled one overwrites the message explaining the cancel.
    private func setState(_ newState: DictationState, generation: Int) {
        guard generation == self.generation else { return }
        state = newState
    }

    /// Puts a deadline on the current state; every change re-arms it.
    private func armWatchdog() {
        watchdog?.cancel()
        watchdog = nil

        let limit: Duration
        switch state {
        case .recording: limit = Limit.recording
        case .transcribing, .injecting: limit = Limit.finishing
        case .idle, .failed: return
        }

        let generation = self.generation
        let expected = state
        watchdog = Task { [weak self] in
            try? await Task.sleep(for: limit)
            guard let self, !Task.isCancelled,
                  self.generation == generation, self.state == expected
            else { return }
            self.timedOut(in: expected)
        }
    }

    private func timedOut(in expected: DictationState) {
        switch expected {
        case .recording:
            // Like a release: what was spoken is there, only the signal was missing.
            end()
        default:
            dictationTask?.cancel()
            closeMicrophone(audio)
            // From here the old dictation belongs to no one.
            generation += 1
            state = .failed("Zeitüberschreitung — Diktat abgebrochen.")
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(3))
                guard let self, case .failed = self.state else { return }
                self.state = .idle
            }
        }
    }
}

enum AudioFormat {
    /// Fallback in case the backend names no format.
    static let fallback: AVAudioFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: 16_000,
        channels: 1,
        interleaved: false
    )!
}
