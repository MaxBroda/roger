import Foundation
import os

/// Pauses and resumes whatever holds macOS's media controls, via
/// `MediaRemote.framework`.
///
/// The framework is private, so it is loaded by hand and every call is optional:
/// if a future macOS drops the symbol, dictation must keep working and this
/// feature must simply stop happening.
///
/// Commands are sent through `MediaRemote` directly, but "is anything playing?"
/// is answered by ``NowPlayingProbing`` instead — reading now-playing info
/// needs an entitlement Apple stopped handing out with macOS 15.4, so this
/// process asks a separate, Apple-signed one that isn't gated the same way.
///
/// `@unchecked Sendable`: the mutable state below is guarded by `lock`.
public final class MediaRemotePlayback: MediaPlaybackControlling, @unchecked Sendable {
    private static let log = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.mbr.roger",
        category: "media"
    )

    private static let frameworkPath =
        "/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote"

    private enum Command: Int32 {
        case play = 0
        case pause = 1
    }

    private typealias SendCommand = @convention(c) (Int32, CFDictionary?) -> Bool

    /// A Bluetooth headset lingers in call mode for up to ~2s after the
    /// microphone closes. Resuming playback into that window plays the first
    /// seconds in mono over the low-quality call channel and ends on an audible
    /// dropout, so on Bluetooth the resume waits this long before it plays.
    private static let bluetoothResumeDelay: Duration = .seconds(2)

    private let preference: MusicPausePreference
    private let nowPlaying: any NowPlayingProbing
    /// Every command runs here, one at a time and in the order it was issued.
    /// Ordering is the point: a resume that overtakes its pause finds nothing to
    /// resume, and the music stays down with nobody left to bring it back. That
    /// it also keeps CoreAudio off the main thread — the first probe costs tens
    /// of milliseconds, and a stalled main thread costs Roger its event tap — is
    /// the second reason.
    private let queue = DispatchQueue(label: "com.mbr.roger.media")
    private let lock = NSLock()
    private var sendCommand: SendCommand?
    private var loadAttempted = false
    /// Guards the resume: without it Roger would start playback that the user
    /// had paused themselves.
    private var didPause = false
    /// The output route as it was before the dictation. Its transport tells the
    /// resume whether to wait out a Bluetooth headset's call mode — see
    /// ``waitForHeadsetToLeaveCallMode(_:)``.
    private var routeBeforePause: AudioDeviceEnumerator.OutputRoute?
    /// Set once on quit, never cleared: from here on nothing may wait any more.
    private var isTerminating = false

    public init(
        preference: MusicPausePreference = MusicPausePreference(),
        nowPlaying: any NowPlayingProbing = NowPlayingMonitor()
    ) {
        self.preference = preference
        self.nowPlaying = nowPlaying
    }

    /// Loading the framework costs a few ms, and the probe spawns a process —
    /// both would otherwise land in the first dictation.
    public func warmUp() {
        guard preference.pausesMusic else { return }
        queue.async {
            _ = self.loadedSendCommand()
            _ = self.nowPlaying.isPlaying()
        }
    }

    public func pauseForDictation() {
        guard preference.pausesMusic else { return }
        queue.async { self.pause() }
    }

    public func resumeAfterDictation(waitingForRoute: Bool) {
        guard waitingForRoute else {
            // The quit path: after the return there may be no process left to
            // run anything, so this one waits for the queue instead of handing
            // the work over. `isTerminating` cuts a running route wait short, so
            // the wait stays a matter of milliseconds.
            lock.withLock { isTerminating = true }
            queue.sync { self.resume(waitingForRoute: false) }
            return
        }
        queue.async { self.resume(waitingForRoute: true) }
    }

    private func pause() {
        // The now-playing probe spawns an osascript process (up to ~0.3s).
        // Asking it *before* pausing meant that, with a Bluetooth headset, the
        // microphone had already flipped the link into call mode while the music
        // kept playing in that low-quality channel for the length of the probe.
        // CoreAudio answers "is the output doing IO right now" instantly, so the
        // pause goes out at once; pausing a silent output is a harmless no-op,
        // and leaving `didPause` false there keeps the resume from starting
        // playback nobody had going.
        guard AudioDeviceEnumerator.isDefaultOutputRunning() else {
            Self.log.info("Output idle — nothing to pause.")
            return
        }
        let route = AudioDeviceEnumerator.defaultOutputRoute()
        guard send(.pause) else { return }
        lock.withLock {
            didPause = true
            routeBeforePause = route
        }
    }

    private func resume(waitingForRoute: Bool) {
        let (shouldResume, baseline) = lock.withLock {
            defer {
                didPause = false
                routeBeforePause = nil
            }
            return (didPause, routeBeforePause)
        }
        guard shouldResume else { return }
        if waitingForRoute { waitForHeadsetToLeaveCallMode(baseline) }
        _ = send(.play)
    }

    /// Only Bluetooth needs this: its link stays in call mode for a moment after
    /// the microphone closes, and starting playback into that plays in mono and
    /// ends on an audible dropout. Built-in and wired outputs never switch modes,
    /// so they resume at once. Reading the sample rate turned out not to be a
    /// reliable tell for every headset, so this just waits a fixed span —
    /// interruptible on quit so shutdown is not held up.
    private func waitForHeadsetToLeaveCallMode(_ baseline: AudioDeviceEnumerator.OutputRoute?) {
        guard baseline?.transport == .bluetooth else { return }
        let deadline = ContinuousClock.now + Self.bluetoothResumeDelay
        while ContinuousClock.now < deadline {
            guard !lock.withLock({ isTerminating }) else { return }
            Thread.sleep(forTimeInterval: 0.05)
        }
    }

    /// `true` only means macOS accepted the command — whether an app acted on it
    /// is not reported back, and apps that never registered with the media
    /// controls simply ignore it.
    private func send(_ command: Command) -> Bool {
        guard let sendCommand = loadedSendCommand() else { return false }
        let accepted = sendCommand(command.rawValue, nil)
        Self.log.info(
            "MediaRemote \(String(describing: command), privacy: .public) accepted=\(accepted, privacy: .public)"
        )
        return accepted
    }

    private func loadedSendCommand() -> SendCommand? {
        lock.withLock {
            if loadAttempted { return sendCommand }
            loadAttempted = true

            guard let handle = dlopen(Self.frameworkPath, RTLD_NOW) else {
                let reason = dlerror().map { String(cString: $0) } ?? "unbekannt"
                Self.log.error("MediaRemote could not be loaded: \(reason, privacy: .public)")
                return nil
            }
            guard let symbol = dlsym(handle, "MRMediaRemoteSendCommand") else {
                Self.log.error("MediaRemote has no MRMediaRemoteSendCommand — feature stays off.")
                return nil
            }
            sendCommand = unsafeBitCast(symbol, to: SendCommand.self)
            return sendCommand
        }
    }
}
