import Foundation
import os

/// Pauses and resumes whatever holds macOS's media controls, via
/// `MediaRemote.framework`.
///
/// The framework is private, so it is loaded by hand and every call is optional:
/// if a future macOS drops the symbol, dictation must keep working and this
/// feature must simply stop happening.
///
/// Only commands are sent through it, never queries: reading the now-playing
/// info from inside an app returns `nil` since macOS 15.4. "Is a player
/// playing?" comes from ``NowPlayingMonitor`` instead, which gets the same
/// information through a channel that is still allowed.
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

    private let preference: MusicPausePreference
    private let nowPlaying: NowPlayingMonitor
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
    /// How the output ran before the dictation. The resume waits for this to
    /// come back — see ``waitForRoute()``.
    private var routeBeforePause: AudioDeviceEnumerator.OutputRoute?
    /// Set once on quit, never cleared: from here on nothing may wait any more.
    private var isTerminating = false

    public init(
        preference: MusicPausePreference = MusicPausePreference(),
        nowPlaying: NowPlayingMonitor = NowPlayingMonitor()
    ) {
        self.preference = preference
        self.nowPlaying = nowPlaying
    }

    /// Called at launch and whenever the setting changes: the monitor is a child
    /// process, so it only runs for users who asked for the feature.
    ///
    /// The warm-up alongside it is for the first dictation: loading the private
    /// framework costs a few milliseconds, the first CoreAudio call around 70 ms.
    public func refreshMonitoring() {
        guard preference.pausesMusic else {
            nowPlaying.stop()
            return
        }
        nowPlaying.start()
        queue.async {
            _ = self.loadedSendCommand()
            _ = AudioDeviceEnumerator.defaultOutputRoute()
        }
    }

    public func stopMonitoring() {
        nowPlaying.stop()
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
        // Only a player that is actually playing. Sound coming out of the
        // machine is not the same thing — a call, an alert or an app merely
        // holding the output device open all look identical to CoreAudio, and
        // acting on them started playback the user had paused (#26).
        guard nowPlaying.state.isPlaying else {
            Self.log.info("No player playing — nothing to pause.")
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
        if waitingForRoute, let baseline { waitForRoute(baseline) }
        _ = send(.play)
    }

    /// A Bluetooth headset stays in call mode for around two seconds after the
    /// microphone closes; music started into that plays in mono, and the switch
    /// back is audible as a dropout. Built-in and wired outputs never change
    /// their rate, so for them this returns on the first check.
    private func waitForRoute(_ baseline: AudioDeviceEnumerator.OutputRoute) {
        let deadline = ContinuousClock.now + .seconds(4)
        while ContinuousClock.now < deadline {
            guard !lock.withLock({ isTerminating }) else { return }
            guard let current = AudioDeviceEnumerator.defaultOutputRoute() else { return }
            // Output was switched or unplugged meanwhile — the old rate says
            // nothing about the new device.
            guard current.deviceID == baseline.deviceID else { return }
            if current.sampleRate == baseline.sampleRate { return }
            Thread.sleep(forTimeInterval: 0.1)
        }
        Self.log.info("Output stayed in call mode — resuming anyway.")
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
