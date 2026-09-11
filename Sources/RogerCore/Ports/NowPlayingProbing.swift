/// Whether a media player is currently playing — not whether the output
/// device carries sound, which a call, a system alert, or a stream's brief
/// tail after being paused would answer just as `true`.
public protocol NowPlayingProbing: Sendable {
    func isPlaying() -> Bool
}
