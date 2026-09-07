import Foundation

/// The push-to-talk rules of ``HoldKeyMonitor``, without the event tap.
///
/// Separated because `CGEvent.tapCreate` needs accessibility permission and is
/// unavailable in CI, while the bugs that actually bit (#1, #2) all sat in these
/// four fields — and only showed up after minutes of idling, the worst kind to
/// reproduce by hand.
///
/// The machine decides, it does not act: timers, replays and the tap itself are
/// effects the caller carries out.
public struct HoldKeyStateMachine: Sendable {
    public enum Input: Sendable {
        case keyDown(keyCode: UInt16, isAutorepeat: Bool, isSynthetic: Bool)
        case keyUp(keyCode: UInt16, isSynthetic: Bool)
        /// macOS pulled the tap. Every event during the stall is lost, a keyUp
        /// included.
        case tapDisabled
    }

    public enum Effect: Equatable, Sendable {
        case reEnableTap
        case startHoldTimer
        case cancelHoldTimer
        case replayShortPress
        case emit(HotkeyEvent)
    }

    public struct Decision: Equatable, Sendable {
        /// Whether the event travels on to the rest of the system.
        public let passesThrough: Bool
        public let effects: [Effect]

        static let pass = Decision(passesThrough: true, effects: [])
        static func swallow(_ effects: [Effect]) -> Decision {
            Decision(passesThrough: false, effects: effects)
        }
    }

    private var binding: HotkeyBinding
    private(set) var isKeyDown = false
    private(set) var isDictating = false
    /// Belt for the marker on replayed events: if it gets lost, this counter
    /// still ends the loop.
    private(set) var pendingReplays = 0

    public init(binding: HotkeyBinding) {
        self.binding = binding
    }

    var keyCode: UInt16 { binding.keyCode }
    var holdThreshold: Duration { binding.holdThreshold }

    public mutating func handle(_ input: Input) -> Decision {
        switch input {
        case .tapDisabled:
            return Decision(passesThrough: true, effects: [.reEnableTap] + interrupt())

        case let .keyDown(keyCode, isAutorepeat, isSynthetic):
            guard keyCode == binding.keyCode else { return .pass }
            guard !consumeReplay(isSynthetic: isSynthetic) else { return .pass }
            guard !isAutorepeat, !isKeyDown else { return .swallow([]) }
            isKeyDown = true
            return .swallow([.startHoldTimer])

        case let .keyUp(keyCode, isSynthetic):
            guard keyCode == binding.keyCode else { return .pass }
            guard !consumeReplay(isSynthetic: isSynthetic) else { return .pass }
            isKeyDown = false
            var effects: [Effect] = [.cancelHoldTimer]
            if isDictating {
                isDictating = false
                effects.append(.emit(.pressEnded))
            } else if binding.replaysShortPress {
                effects.append(.replayShortPress)
            }
            return .swallow(effects)
        }
    }

    /// The hold time is up: the press counts as push-to-talk.
    public mutating func holdThresholdElapsed() -> Effect? {
        guard isKeyDown, !isDictating else { return nil }
        isDictating = true
        return .emit(.pressBegan)
    }

    /// One replayed event was posted and is expected to come back through the tap.
    public mutating func expectReplay() {
        pendingReplays += 1
    }

    /// A replayed event never came back — otherwise a later real press counts as
    /// ours and is swallowed.
    public mutating func replayResetElapsed() {
        pendingReplays = 0
    }

    /// Binds a different key. A dictation running on the old key has to end, or
    /// its session never hears the release and the bubble stays up.
    public mutating func rebind(to newBinding: HotkeyBinding) -> [Effect] {
        guard newBinding != binding else { return [] }
        binding = newBinding
        return interrupt()
    }

    /// For teardown: the caller closes the stream itself, so no `.pressEnded`.
    public mutating func reset() {
        isKeyDown = false
        isDictating = false
        pendingReplays = 0
    }

    private mutating func consumeReplay(isSynthetic: Bool) -> Bool {
        guard isSynthetic || pendingReplays > 0 else { return false }
        pendingReplays = max(0, pendingReplays - 1)
        return true
    }

    /// Gives up the hold state instead of waiting forever for a keyUp that was
    /// swallowed with the tap.
    private mutating func interrupt() -> [Effect] {
        isKeyDown = false
        pendingReplays = 0
        var effects: [Effect] = [.cancelHoldTimer]
        if isDictating {
            isDictating = false
            effects.append(.emit(.pressEnded))
        }
        return effects
    }
}
