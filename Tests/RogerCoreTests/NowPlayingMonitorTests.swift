import Testing

@testable import RogerCore

/// Only ``NowPlayingMonitor/parse(_:)`` is pure enough to test directly — the
/// rest is a subprocess call. These pin down the forgiving-on-purpose parsing:
/// only the last line counts, and anything that doesn't look right reads as
/// "nothing playing" rather than throwing.
struct NowPlayingMonitorTests {
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
