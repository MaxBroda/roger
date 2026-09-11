import Foundation
import os

/// Answers ``NowPlayingProbing`` by running a JXA script through `osascript`.
///
/// `MediaRemote`'s now-playing info needs an entitlement Apple stopped handing
/// out with macOS 15.4 — reading it from inside Roger's own process returns
/// `nil`. `osascript` is Apple-signed and unaffected by that gate, so the
/// script (``Resources/now-playing.js`` in the bundle) reads the same private
/// class from its own process instead.
///
/// Any failure here — the script missing, the call timing out, unparsable
/// output — is read as "nothing is playing". Guessing "playing" is what
/// caused Roger to resume music nobody had started (issue #26); guessing
/// "not playing" only risks not muting something, which is silent and
/// recoverable.
public struct NowPlayingMonitor: NowPlayingProbing {
    private static let log = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.mbr.roger",
        category: "media"
    )

    private let scriptURL: URL?
    private let timeout: TimeInterval

    public init(bundle: Bundle = .main, timeout: TimeInterval = 0.3) {
        self.scriptURL = bundle.url(forResource: "now-playing", withExtension: "js")
        self.timeout = timeout
    }

    public func isPlaying() -> Bool {
        guard let scriptURL else {
            Self.log.error("now-playing.js is missing from the bundle — treating as nothing playing.")
            return false
        }
        guard let output = run(scriptURL) else { return false }
        return Self.parse(output)
    }

    private func run(_ scriptURL: URL) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-l", "JavaScript", scriptURL.path]
        let stdout = Pipe()
        process.standardOutput = stdout
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            Self.log.error("osascript could not launch: \(error.localizedDescription, privacy: .public)")
            return nil
        }

        let group = DispatchGroup()
        group.enter()
        process.terminationHandler = { _ in group.leave() }
        if group.wait(timeout: .now() + timeout) == .timedOut {
            process.terminate()
            Self.log.error("osascript timed out after \(timeout, privacy: .public)s — treating as nothing playing.")
            return nil
        }
        guard process.terminationStatus == 0 else { return nil }

        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)
    }

    /// The script's stdout is one JSON object, but only the *last* line counts
    /// — kept forgiving on purpose in case a future macOS starts writing
    /// something ahead of it.
    static func parse(_ output: String) -> Bool {
        guard
            let line = output.split(separator: "\n").last,
            let data = line.data(using: .utf8),
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let playing = json["playing"] as? Bool
        else { return false }
        return playing
    }
}
