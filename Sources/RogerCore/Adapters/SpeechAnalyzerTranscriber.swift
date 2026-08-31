import AVFAudio
import Foundation
import Speech

/// On-device transcription via the `SpeechAnalyzer` API of macOS 26. The system
/// fetches the language model itself; ``prepare()`` kicks that off and reserves
/// the locale so it does not get evicted.
public actor SpeechAnalyzerTranscriber: Transcribing, LocaleConfigurable, ContextBiasing {
    /// Progress, 0…1.
    public typealias DownloadProgressHandler = @Sendable (Double) -> Void

    private let preference: LanguagePreference
    private let catalog: LanguageCatalog
    private let preset: SpeechTranscriber.Preset
    private let onDownloadProgress: DownloadProgressHandler?

    private var locale: Locale?
    private var contextPhrases: [String] = []

    public init(
        preference: LanguagePreference = LanguagePreference(),
        catalog: LanguageCatalog = .default,
        preset: SpeechTranscriber.Preset = .transcription,
        onDownloadProgress: DownloadProgressHandler? = nil
    ) {
        self.preference = preference
        self.catalog = catalog
        self.preset = preset
        self.onDownloadProgress = onDownloadProgress
    }

    public func prepare() async throws {
        guard SpeechTranscriber.isAvailable else {
            throw RogerError.transcriberUnavailable(locale: "—")
        }
        let offered = await availableLocales()
        guard let chosen = preference.resolve(against: offered) else {
            throw RogerError.transcriberUnavailable(locale: "—")
        }
        try await activate(chosen)
    }

    public func preferredAudioFormat() async -> AVAudioFormat? {
        await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [makeModule()])
    }

    public func transcribe(_ audio: AsyncStream<AudioChunk>) async throws -> Transcript? {
        let module = makeModule()
        let analyzer = SpeechAnalyzer(modules: [module])
        let (inputs, inputContinuation) = AsyncStream<AnalyzerInput>.makeStream(
            bufferingPolicy: .unbounded
        )

        // Pumps microphone buffers into the analyzer and finishes it when the
        // recording ends — otherwise `module.results` never ends.
        let pump = Task {
            for await chunk in audio {
                inputContinuation.yield(AnalyzerInput(buffer: chunk.buffer))
            }
            inputContinuation.finish()
            try? await analyzer.finalizeAndFinishThroughEndOfInput()
        }

        do {
            await applyContext(to: analyzer)
            try await analyzer.start(inputSequence: inputs)

            var text = AttributedString()
            for try await result in module.results {
                text.append(result.text)
            }
            await pump.value
            return Transcript(String(text.characters))
        } catch {
            pump.cancel()
            inputContinuation.finish()
            await analyzer.cancelAndFinishNow()
            throw error
        }
    }

    public func setContextPhrases(_ phrases: [String]) {
        contextPhrases = phrases
    }

    /// Before `start`, because recognition begins with the first buffer. A failure
    /// here must not block a dictation — without context it recognises worse, but
    /// it recognises.
    private func applyContext(to analyzer: SpeechAnalyzer) async {
        guard !contextPhrases.isEmpty else { return }
        let context = AnalysisContext()
        context.contextualStrings = [.general: contextPhrases]
        try? await analyzer.setContext(context)
    }

    public func activeLocale() async -> Locale {
        locale ?? Locale.current
    }

    public func availableLocales() async -> [Locale] {
        catalog.filter(await SpeechTranscriber.supportedLocales)
    }

    public func installedLocales() async -> [Locale] {
        catalog.filter(await SpeechTranscriber.installedLocales)
    }

    public func use(_ newLocale: Locale) async throws {
        try await activate(newLocale)
        // Store only after a successful switch, or the app starts next time in a
        // language that would not load.
        preference.store(newLocale)
    }

    private func activate(_ candidate: Locale) async throws {
        guard let resolved = await SpeechTranscriber.supportedLocale(equivalentTo: candidate) else {
            throw RogerError.transcriberUnavailable(locale: candidate.identifier)
        }

        // A second `reserve` for the same locale can fail at the limit of five
        // reservations and take the whole dictation stack with it.
        if locale == resolved { return }

        let module = SpeechTranscriber(locale: resolved, preset: preset)
        if let request = try await AssetInventory.assetInstallationRequest(supporting: [module]) {
            try await download(request)
        }

        // Reservations are capped at five, so release the old one.
        if let previous = locale, previous != resolved {
            await AssetInventory.release(reservedLocale: previous)
        }
        try await AssetInventory.reserve(locale: resolved)

        locale = resolved
    }

    private func download(_ request: AssetInstallationRequest) async throws {
        guard let onDownloadProgress else {
            try await request.downloadAndInstall()
            return
        }

        // Polling instead of KVO: saves keeping an observation token, and progress
        // only changes visibly every few hundred milliseconds.
        let poller = Task {
            while !Task.isCancelled {
                onDownloadProgress(request.progress.fractionCompleted)
                try? await Task.sleep(for: .milliseconds(200))
            }
        }
        defer { poller.cancel() }

        try await request.downloadAndInstall()
    }

    private func makeModule() -> SpeechTranscriber {
        SpeechTranscriber(locale: locale ?? Locale.current, preset: preset)
    }
}
