import AVFAudio
import Testing

@testable import RogerCore

/// The second hotkey shares one `DictationSession` with the first instead of
/// getting its own (see the LLM-cleanup-hotkey plan) — the guard that makes
/// that safe is `state`/`activeMode`, not a second state machine. These pin
/// down the two ways that guard could quietly fail: the other key starting a
/// second recording, or the other key's release cutting the running one off.
@MainActor
struct DictationSessionModeTests {
    /// `send` before `run()` has called `start()` would drop the event on the
    /// floor (`continuation` still `nil`) — `waitUntilStarted()` closes that race
    /// instead of papering over it with a sleep.
    private final class FakeHotkey: HotkeyMonitoring, @unchecked Sendable {
        private var continuation: AsyncStream<HotkeyEvent>.Continuation?
        private var hasStarted = false
        private var startContinuation: CheckedContinuation<Void, Never>?

        func start() throws -> AsyncStream<HotkeyEvent> {
            let (stream, continuation) = AsyncStream<HotkeyEvent>.makeStream()
            self.continuation = continuation
            hasStarted = true
            startContinuation?.resume()
            startContinuation = nil
            return stream
        }

        func stop() {
            continuation?.finish()
            continuation = nil
        }

        func send(_ event: HotkeyEvent) {
            continuation?.yield(event)
        }

        func waitUntilStarted() async {
            if hasStarted { return }
            await withCheckedContinuation { startContinuation = $0 }
        }
    }

    private struct FakeAudio: AudioCapturing {
        func start(outputFormat: AVAudioFormat) throws -> AsyncStream<AudioChunk> {
            AsyncStream { $0.finish() }
        }
        func stop() {}
    }

    /// Blocks `transcribe` until the test opens the gate — the window in which
    /// the cross-key guard has to hold.
    private actor Gate {
        private var isOpen = false
        private var continuation: CheckedContinuation<Void, Never>?

        func open() {
            isOpen = true
            continuation?.resume()
            continuation = nil
        }

        func wait() async {
            if isOpen { return }
            await withCheckedContinuation { continuation = $0 }
        }
    }

    private struct FakeTranscriber: Transcribing {
        let gate: Gate
        let text: String
        func prepare() async throws {}
        func preferredAudioFormat() async -> AVAudioFormat? { nil }
        func transcribe(_ audio: AsyncStream<AudioChunk>) async throws -> Transcript? {
            for await _ in audio {}
            await gate.wait()
            return Transcript(text)
        }
    }

    private struct TaggingFormatter: TextFormatting {
        let tag: String
        func format(_ transcript: Transcript) async throws -> FormattingResult {
            FormattingResult(transcript: transcript.replacingText("\(tag):\(transcript.text)"))
        }
    }

    private final class FakeInjector: TextInjecting, @unchecked Sendable {
        private(set) var injected: [String] = []
        func inject(_ transcript: Transcript) async throws { injected.append(transcript.text) }
    }

    private struct FakeMedia: MediaPlaybackControlling {
        func warmUp() {}
        func pauseForDictation() {}
        func resumeAfterDictation(waitingForRoute: Bool) {}
    }

    private func waitUntil(
        timeout: Duration = .seconds(1),
        _ condition: () -> Bool
    ) async {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if condition() { return }
            try? await Task.sleep(for: .milliseconds(5))
        }
        Issue.record("condition not met within \(timeout)")
    }

    @Test func zweiteTasteWaehltDenLLMFormatterUndFremdeTastenStörenNicht() async throws {
        let primaryHotkey = FakeHotkey()
        let secondaryHotkey = FakeHotkey()
        let injector = FakeInjector()
        let gate = Gate()

        let session = DictationSession(
            hotkey: primaryHotkey,
            llmHotkey: secondaryHotkey,
            audio: FakeAudio(),
            transcriber: FakeTranscriber(gate: gate, text: "hallo welt"),
            formatter: TaggingFormatter(tag: "STD"),
            llmFormatter: TaggingFormatter(tag: "LLM"),
            injector: injector,
            media: FakeMedia(),
            spectrumBandCount: 1
        )

        let runTask = Task { try? await session.run() }
        defer { runTask.cancel() }
        await primaryHotkey.waitUntilStarted()
        await secondaryHotkey.waitUntilStarted()

        secondaryHotkey.send(.pressBegan)
        await waitUntil { session.state == .recording }

        // A press of the *other* key while this one is recording must be a
        // no-op — not a second dictation racing the same microphone.
        primaryHotkey.send(.pressBegan)
        try await Task.sleep(for: .milliseconds(20))
        #expect(session.state == .recording)

        // Releasing that other key must not cut the running one off either.
        primaryHotkey.send(.pressEnded)
        try await Task.sleep(for: .milliseconds(20))
        #expect(session.state == .recording)

        await gate.open()
        secondaryHotkey.send(.pressEnded)
        await waitUntil { injector.injected.count == 1 }

        #expect(injector.injected == ["LLM:hallo welt"])
    }

    @Test func erstTasteBleibtBeimStandardFormatter() async throws {
        let primaryHotkey = FakeHotkey()
        let secondaryHotkey = FakeHotkey()
        let injector = FakeInjector()
        let gate = Gate()
        await gate.open()

        let session = DictationSession(
            hotkey: primaryHotkey,
            llmHotkey: secondaryHotkey,
            audio: FakeAudio(),
            transcriber: FakeTranscriber(gate: gate, text: "hallo welt"),
            formatter: TaggingFormatter(tag: "STD"),
            llmFormatter: TaggingFormatter(tag: "LLM"),
            injector: injector,
            media: FakeMedia(),
            spectrumBandCount: 1
        )

        let runTask = Task { try? await session.run() }
        defer { runTask.cancel() }
        await primaryHotkey.waitUntilStarted()

        // The gate is already open, so this dictation runs to completion on its
        // own — no need to time a `.pressEnded` against it, unlike the other test.
        primaryHotkey.send(.pressBegan)
        await waitUntil { injector.injected.count == 1 }

        #expect(injector.injected == ["STD:hallo welt"])
    }
}
