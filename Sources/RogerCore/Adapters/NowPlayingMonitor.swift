import Foundation
import os

/// Knows whether a media player is currently playing, and which one.
///
/// The answer comes from the vendored MediaRemote adapter, running as a
/// long-lived child process: `/usr/bin/perl` is entitled to read the now-playing
/// information that an app itself no longer gets (see
/// `Sources/MediaRemoteAdapter/README.md`). It prints one JSON line per change,
/// so the state here is current without anyone asking.
///
/// A single query would also work but costs 130 ms — long enough that the pause
/// would leave only after the microphone is already open, which is exactly the
/// moment the music must be gone.
///
/// Everything is optional: no bundle, no script, no perl, a dead process — the
/// state stays "nothing playing", and the caller pauses nothing. Never guessing
/// is the point; guessing is what started playback nobody asked for.
///
/// `@unchecked Sendable`: the mutable state below is guarded by `lock`.
public final class NowPlayingMonitor: @unchecked Sendable {
    public struct State: Sendable, Equatable {
        public let isPlaying: Bool
        public let bundleIdentifier: String?

        static let unknown = State(isPlaying: false, bundleIdentifier: nil)
    }

    private static let log = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.mbr.roger",
        category: "media"
    )

    /// Long enough that a seek or a track change does not produce a burst,
    /// short enough to be settled before the next dictation starts.
    private static let debounceMilliseconds = 200
    private static let restartDelay: TimeInterval = 5

    private let lock = NSLock()
    private var process: Process?
    private var buffer = Data()
    private var current: State = .unknown
    private var wantsToRun = false

    public init() {}

    public var state: State {
        lock.withLock { current }
    }

    /// Idempotent — a second call while the process runs does nothing.
    public func start() {
        lock.withLock { wantsToRun = true }
        launch()
    }

    public func stop() {
        let running: Process? = lock.withLock {
            wantsToRun = false
            current = .unknown
            defer { process = nil }
            return process
        }
        running?.terminate()
    }

    private func launch() {
        guard lock.withLock({ wantsToRun && process == nil }) else { return }

        guard let script = Bundle.main.url(forResource: "mediaremote-adapter", withExtension: "pl"),
              let framework = Self.frameworkURL
        else {
            Self.log.error("MediaRemote adapter not found in the bundle — music pausing stays off.")
            return
        }

        // A crash leaves the child behind — the script has no watchdog of its
        // own. Matching on our own script path keeps this to Roger's instances:
        // other apps ship the same adapter from their own bundles.
        terminateOrphans(scriptPath: script.path)

        let child = Process()
        child.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        child.arguments = [
            script.path,
            framework.path,
            "stream",
            "--no-diff",
            "--debounce=\(Self.debounceMilliseconds)",
        ]
        let pipe = Pipe()
        child.standardOutput = pipe
        child.standardError = FileHandle.nullDevice

        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            self?.consume(handle.availableData)
        }
        child.terminationHandler = { [weak self] _ in
            self?.handleTermination()
        }

        do {
            try child.run()
            lock.withLock { self.process = child }
            Self.log.info("Now-playing monitor started.")
        } catch {
            Self.log.error("Now-playing monitor failed to start: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// The adapter dying is not fatal — it comes back. Without the delay a
    /// permanently failing script would spin.
    private func handleTermination() {
        let shouldRestart: Bool = lock.withLock {
            process = nil
            current = .unknown
            return wantsToRun
        }
        guard shouldRestart else { return }
        Self.log.info("Now-playing monitor ended — restarting.")
        DispatchQueue.global().asyncAfter(deadline: .now() + Self.restartDelay) { [weak self] in
            self?.launch()
        }
    }

    /// One JSON object per line. Partial lines are normal: the payload carries
    /// artwork and arrives in several reads.
    private func consume(_ data: Data) {
        guard !data.isEmpty else { return }
        let lines: [Data] = lock.withLock {
            buffer.append(data)
            var complete: [Data] = []
            while let newline = buffer.firstIndex(of: UInt8(ascii: "\n")) {
                complete.append(buffer[buffer.startIndex..<newline])
                buffer = buffer[buffer.index(after: newline)...]
            }
            return complete
        }
        for line in lines { apply(line) }
    }

    private func apply(_ line: Data) {
        guard
            let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
            let payload = object["payload"] as? [String: Any]
        else { return }

        // An empty payload is the adapter saying there is no now-playing
        // session at all.
        let newState = State(
            isPlaying: payload["playing"] as? Bool ?? false,
            bundleIdentifier: payload["bundleIdentifier"] as? String
        )
        let changed: Bool = lock.withLock {
            guard current != newState else { return false }
            current = newState
            return true
        }
        guard changed else { return }
        Self.log.info(
            "Now playing: playing=\(newState.isPlaying, privacy: .public) app=\(newState.bundleIdentifier ?? "-", privacy: .public)"
        )
    }

    private func terminateOrphans(scriptPath: String) {
        let pkill = Process()
        pkill.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
        pkill.arguments = ["-f", scriptPath]
        pkill.standardOutput = FileHandle.nullDevice
        pkill.standardError = FileHandle.nullDevice
        try? pkill.run()
        pkill.waitUntilExit()
        // Exit code 0 means it found one, which only happens after a crash.
        if pkill.terminationStatus == 0 {
            Self.log.info("Left-over now-playing monitor terminated.")
        }
    }

    /// Sits next to the executable, put there by `scripts/bundle.sh`.
    private static var frameworkURL: URL? {
        guard let executable = Bundle.main.executableURL else { return nil }
        let url = executable
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "Frameworks/MediaRemoteAdapter.framework")
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }
}
