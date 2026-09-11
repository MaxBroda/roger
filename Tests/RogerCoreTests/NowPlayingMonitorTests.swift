import Foundation
import Testing

@testable import RogerCore

private struct StubScriptRunner: NowPlayingScriptRunning {
    let output: String?
    func run(scriptURL: URL, timeout: TimeInterval) -> String? { output }
}

/// The repo's `Resources/` directory as a `Bundle` — the real app has
/// `now-playing.js` copied into its bundle at package time, which `swift
/// test` never does, so `.main` alone can't stand in for "resource present".
private let repoResourcesBundle = Bundle(
    path: URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("Resources")
        .path
)!

/// ``NowPlayingMonitor/parse(_:)`` is pure and tested directly. The subprocess
/// call is stood in for by ``StubScriptRunner``, which represents every one of
/// its failure modes (launch failure, non-zero exit, timeout) the same way the
/// real runner does: as a `nil` result — that's the only thing ``isPlaying()``
/// can observe from them anyway.
struct NowPlayingMonitorTests {
    @Test func fehlendesSkriptImBundleIstNichtsSpieltNicht() {
        let bundleOhneSkript = Bundle(path: NSTemporaryDirectory())!
        let monitor = NowPlayingMonitor(bundle: bundleOhneSkript)
        #expect(monitor.isPlaying() == false)
    }

    @Test func fehlgeschlagenerSubprocessIstNichtsSpieltNicht() {
        let monitor = NowPlayingMonitor(
            bundle: repoResourcesBundle,
            timeout: 0.3,
            runner: StubScriptRunner(output: nil)
        )
        #expect(monitor.isPlaying() == false)
    }

    @Test func erfolgreicherSubprocessLiefertGeparstesErgebnis() {
        let monitor = NowPlayingMonitor(
            bundle: repoResourcesBundle,
            timeout: 0.3,
            runner: StubScriptRunner(output: #"{"playing":true}"#)
        )
        #expect(monitor.isPlaying() == true)
    }
    @Test func liestPlayingTrue() {
        #expect(NowPlayingMonitor.parse(#"{"playing":true}"#) == true)
    }

    @Test func liestPlayingFalse() {
        #expect(NowPlayingMonitor.parse(#"{"playing":false}"#) == false)
    }

    @Test func nimmtNurDieLetzteZeile() {
        let output = "irgendein Rauschen davor\n" + #"{"playing":true}"#
        #expect(NowPlayingMonitor.parse(output) == true)
    }

    @Test func leererOutputIstNichtsSpieltNicht() {
        #expect(NowPlayingMonitor.parse("") == false)
    }

    @Test func kaputtesJSONIstNichtsSpieltNicht() {
        #expect(NowPlayingMonitor.parse("das ist kein JSON") == false)
    }

    @Test func fehlendesFeldIstNichtsSpieltNicht() {
        #expect(NowPlayingMonitor.parse(#"{"other":true}"#) == false)
    }
}
