import AppKit
import Observation
import RogerCore
import os

/// The application service: owns the dictation stack and is what the windows
/// see. The session knows only ports, the windows only UI — what both need lives
/// here: available languages, what is loading, what went wrong.
@MainActor
@Observable
public final class RogerApp {
    struct LanguageChoice: Identifiable {
        let locale: Locale
        let isInstalled: Bool
        var id: String { locale.identifier }
        var name: String { locale.nativeDisplayName }
    }

    private(set) var state: DictationState = .idle
    private(set) var bands = [Float](repeating: 0, count: Design.Spectrum.bandCount)
    /// What Roger is preparing — loading a model, switching language.
    private(set) var preparing: String?
    private(set) var downloadFraction: Double?
    private(set) var languages: [LanguageChoice] = []
    private(set) var activeLocale: Locale?
    private(set) var hotkey: HotkeyBinding
    /// No Dock icon, no app switcher entry, no window on launch.
    private(set) var isMenuBarOnly: Bool

    let dictionary: DictionaryStore
    let history: HistoryStore

    /// Menu bar and HUD are AppKit and don't observe — they get called.
    var onStateChange: ((DictationState) -> Void)?
    var onSpectrum: (([Float]) -> Void)?
    var onStatusChange: (() -> Void)?
    /// Only the delegate can switch modes — the activation policy belongs to the
    /// process, not to this service.
    var onMenuBarModeChange: (() -> Void)?

    /// The menu bar message goes away again — stack failures also belong in the
    /// system log.
    private static let log = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "de.mbr.roger",
        category: "dictation"
    )

    /// The usual reason a stack fails to come up is a backend that is briefly
    /// unavailable — that resolves itself, just not immediately.
    private static let retryDelays: [Duration] = [.seconds(5), .seconds(20), .seconds(60)]

    private let hotkeyPreference = HotkeyPreference()
    private let menuBarModePreference = MenuBarModePreference()
    private var transcriber: SpeechAnalyzerTranscriber?
    private var monitor: HoldKeyMonitor?
    private var session: DictationSession?
    private var runTask: Task<Void, Never>?
    private var retryTask: Task<Void, Never>?
    private var failureResetTask: Task<Void, Never>?
    private var startAttempt = 0

    public init(dictionary: DictionaryStore = DictionaryStore(), history: HistoryStore = HistoryStore()) {
        self.dictionary = dictionary
        self.history = history
        self.hotkey = hotkeyPreference.binding
        self.isMenuBarOnly = menuBarModePreference.isMenuBarOnly
    }

    var isRunning: Bool { session != nil }

    /// Only once permissions are in place — the event tap would fail otherwise.
    func startDictationStack() {
        guard session == nil else { return }
        retryTask?.cancel()
        retryTask = nil
        // A new attempt does not start in the failed state.
        if case .failed = state { apply(.idle) }

        let transcriber = SpeechAnalyzerTranscriber(
            preference: LanguagePreference(),
            onDownloadProgress: { [weak self] fraction in
                Task { @MainActor in self?.reportDownload(fraction) }
            }
        )
        self.transcriber = transcriber

        let monitor = HoldKeyMonitor(binding: hotkey)
        self.monitor = monitor

        let session = DictationSession(
            hotkey: monitor,
            audio: MicrophoneCapture(),
            transcriber: transcriber,
            formatter: DictionaryCorrector(store: dictionary),
            injector: PasteboardInjector(),
            spectrumBandCount: Design.Spectrum.bandCount
        )
        session.onStateChange = { [weak self] state in self?.apply(state) }
        session.onSpectrum = { [weak self] bands in self?.apply(bands: bands) }
        session.onCompleted = { [weak self] result in
            self?.history.append(result)
        }
        self.session = session

        // Terms go to recognition at launch and after every change, including one
        // made to the file from outside.
        dictionary.onChange = { [weak self] dictionary in
            self?.pushContext(dictionary)
        }
        pushContext(dictionary.dictionary)

        beginPreparing("Lade Sprachmodell …")
        runTask = Task { [weak self] in
            do {
                try await transcriber.prepare()
                self?.finishPreparing()
                await self?.refreshLanguages()
                // Once the stack is up, the next failure counts from zero again.
                self?.startAttempt = 0
                try await session.run()
            } catch {
                self?.handleStackFailure(error)
            }
        }
    }

    func shutdown() {
        retryTask?.cancel()
        failureResetTask?.cancel()
        runTask?.cancel()
        session?.shutdown()
    }

    /// Tear down, report, retry: if `.failed` stayed, the event tap would be gone
    /// with it — bubble stuck, key dead, only a relaunch helps.
    private func handleStackFailure(_ error: any Error) {
        Self.log.error("Diktatstapel gescheitert: \(error.localizedDescription, privacy: .public)")
        teardownStack()
        apply(.failed(error.localizedDescription))
        scheduleRetry()
    }

    private func teardownStack() {
        runTask?.cancel()
        runTask = nil
        dictionary.onChange = nil
        session?.shutdown()
        session = nil
        monitor = nil
        transcriber = nil
    }

    private func scheduleRetry() {
        retryTask?.cancel()
        retryTask = nil
        // Three failures mean it is not about timing.
        guard startAttempt < Self.retryDelays.count else {
            Self.log.error("Diktatstapel bleibt aus — kein weiterer Versuch.")
            return
        }
        let delay = Self.retryDelays[startAttempt]
        startAttempt += 1
        retryTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard let self, !Task.isCancelled else { return }
            self.startDictationStack()
        }
    }

    var canRecord: Bool { session != nil && state == .idle }
    var isRecording: Bool { state == .recording }

    func startDictation() {
        session?.startDictation()
    }

    func stopDictation() {
        session?.stopDictation()
    }

    func toggleDictation() {
        session?.toggleDictation()
    }

    func refreshLanguages() async {
        guard let transcriber else { return }
        let available = await transcriber.availableLocales()
        let installed = await transcriber.installedLocales()
        activeLocale = await transcriber.activeLocale()
        languages = available.map { locale in
            LanguageChoice(
                locale: locale,
                isInstalled: installed.contains { $0.matches(locale) }
            )
        }
        onStatusChange?()
    }

    func select(language locale: Locale) {
        guard let transcriber else { return }
        beginPreparing("Wechsle zu \(locale.nativeDisplayName) …")
        Task {
            do {
                try await transcriber.use(locale)
                finishPreparing()
            } catch {
                apply(.failed(error.localizedDescription))
            }
            await refreshLanguages()
        }
    }

    func rebindHotkey(to binding: HotkeyBinding) {
        guard binding != hotkey else { return }
        hotkeyPreference.store(binding)
        hotkey = binding
        monitor?.rebind(to: binding)
        onStatusChange?()
    }

    func setMenuBarOnly(_ isMenuBarOnly: Bool) {
        guard isMenuBarOnly != self.isMenuBarOnly else { return }
        menuBarModePreference.store(isMenuBarOnly)
        self.isMenuBarOnly = isMenuBarOnly
        onMenuBarModeChange?()
    }

    /// One line, the same everywhere: menu bar, title bar, status field.
    var statusLine: String {
        if let downloadFraction {
            return "Lade Sprachmodell \(Int(downloadFraction * 100)) %"
        }
        if let preparing { return preparing }
        switch state {
        case .idle: return session == nil ? "Einrichtung nicht abgeschlossen" : "Bereit"
        case .recording: return "Aufnahme läuft"
        case .transcribing: return "Transkribiere"
        case .injecting: return "Füge ein"
        case .failed(let message): return message
        }
    }

    private func apply(_ newState: DictationState) {
        // A real state ends any preparing message — otherwise a stale "loading
        // 100 %" that overtook the completion would stay up.
        if newState != .idle { finishPreparing() }
        state = newState
        onStateChange?(newState)
        onStatusChange?()
        armFailureReset()
    }

    /// `.failed` is a message, not a state to stay in — staying would leave key
    /// and button dead until relaunch. Only while the stack is up: once torn down,
    /// the failure is the truth and stays.
    private func armFailureReset() {
        failureResetTask?.cancel()
        failureResetTask = nil
        guard case .failed = state, session != nil else { return }
        failureResetTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(6))
            guard let self, !Task.isCancelled, case .failed = self.state else { return }
            self.apply(.idle)
        }
    }

    private func apply(bands newBands: [Float]) {
        guard newBands.count == bands.count else { return }
        bands = newBands
        onSpectrum?(newBands)
    }

    private func beginPreparing(_ label: String) {
        preparing = label
        downloadFraction = nil
        onStatusChange?()
    }

    private func finishPreparing() {
        guard preparing != nil || downloadFraction != nil else { return }
        preparing = nil
        downloadFraction = nil
        onStatusChange?()
    }

    private func reportDownload(_ fraction: Double) {
        guard preparing != nil else { return }
        downloadFraction = fraction
        onStatusChange?()
    }

    private func pushContext(_ dictionary: PhraseDictionary) {
        guard let transcriber else { return }
        let phrases = dictionary.biasPhrases()
        Task { await transcriber.setContextPhrases(phrases) }
    }
}
