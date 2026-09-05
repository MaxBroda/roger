/// Playback of *other* apps — music, videos, whatever holds the system's media
/// controls. Roger only silences it for the length of a dictation.
///
/// Every call returns right away and takes effect in the order it was made —
/// pause and resume must never overtake each other, or a resume runs into a
/// dictation that has not paused yet and leaves the music down for good.
public protocol MediaPlaybackControlling: Sendable {
    /// Brings the implementation in line with the current setting — the state it
    /// needs may cost a background process, which nobody should pay for a
    /// feature they switched off. Also pays the one-off setup cost up front, so
    /// the first dictation does not.
    func refreshMonitoring()

    /// Gives up whatever ``refreshMonitoring()`` started.
    func stopMonitoring()
    /// Pauses playback if the user asked for it and something is actually
    /// playing. Doing nothing is a valid outcome.
    func pauseForDictation()
    /// Resumes only what ``pauseForDictation()`` paused itself. Safe to call
    /// more than once and safe to call without a preceding pause.
    ///
    /// - Parameter waitingForRoute: hold the music back until the output is
    ///   out of call mode again — a Bluetooth headset needs about two seconds
    ///   for that, and starting earlier plays it in mono. Pass `false` when
    ///   there is no time left to wait, such as on quit — then the call also
    ///   waits for the resume itself, because after a quit nothing runs any
    ///   more.
    func resumeAfterDictation(waitingForRoute: Bool)
}
