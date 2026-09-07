// `CGEvent` is not Sendable, even though the tap callback runs on one thread.
@preconcurrency import CoreGraphics
import Foundation

/// Turns an ordinary key into a push-to-talk key.
///
/// Esc already has a job — swallowing it would kill it system-wide. So every
/// press is held back and a timer started: released before the threshold →
/// ordinary keystroke, replayed with a marker (cost: the threshold as latency);
/// timer elapsed → push-to-talk, press stays swallowed.
///
/// `@unchecked Sendable` rather than `@MainActor`, although all state is touched
/// on the main thread only: a `MainActor.assumeIsolated` in the callback makes
/// the concurrency runtime check its executor on every keystroke, which killed
/// Roger reproducibly with SIGSEGV (`swift_task_isCurrentExecutorWithFlags`
/// under `HoldKeyMonitor.start()`).
public final class HoldKeyMonitor: HotkeyMonitoring, @unchecked Sendable {
    /// Marks events we posted ourselves.
    private static let syntheticMarker: Int64 = 0x524F_4745  // "ROGE"

    /// The rules live here, testable without a tap. This class only translates
    /// `CGEvent` into inputs and effects back into CoreGraphics calls.
    private var machine: HoldKeyStateMachine

    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    /// Keeps the monitor alive as long as the tap carries it as `userInfo` —
    /// otherwise the callback would point at freed memory.
    private var tapContext: Unmanaged<HoldKeyMonitor>?
    private var continuation: AsyncStream<HotkeyEvent>.Continuation?
    private var holdTimer: DispatchSourceTimer?
    private var replayResetTimer: DispatchSourceTimer?

    public init(binding: HotkeyBinding = .escHold) {
        self.machine = HoldKeyStateMachine(binding: binding)
    }

    /// Binds a different key. The tap stays up — it listens to all keys anyway,
    /// and rebuilding it would only trigger the TCC check again.
    public func rebind(to newBinding: HotkeyBinding) {
        apply(machine.rebind(to: newBinding))
    }

    public func start() throws -> AsyncStream<HotkeyEvent> {
        stop()

        let mask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue)
        // Nothing here may touch the concurrency runtime, and nothing may take
        // long: macOS revokes the tap if we are too slow.
        let callback: CGEventTapCallBack = { _, type, event, refcon in
            guard let refcon else { return Unmanaged.passUnretained(event) }
            let monitor = Unmanaged<HoldKeyMonitor>.fromOpaque(refcon).takeUnretainedValue()
            return monitor.handle(type: type, event: event)
        }

        let context = Unmanaged.passRetained(self)
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(mask),
            callback: callback,
            userInfo: context.toOpaque()
        ) else {
            context.release()
            throw RogerError.hotkeyTapUnavailable
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        self.tap = tap
        self.runLoopSource = source
        self.tapContext = context

        let (stream, continuation) = AsyncStream<HotkeyEvent>.makeStream(
            bufferingPolicy: .bufferingNewest(8)
        )
        self.continuation = continuation
        return stream
    }

    public func stop() {
        cancelHoldTimer()
        replayResetTimer?.cancel()
        replayResetTimer = nil
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        tap = nil
        runLoopSource = nil
        // Only after the tap is gone can no callback reach this pointer.
        tapContext?.release()
        tapContext = nil
        machine.reset()
        continuation?.finish()
        continuation = nil
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        let input: HoldKeyStateMachine.Input
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            input = .tapDisabled
        case .keyDown:
            input = .keyDown(
                keyCode: keyCode(of: event),
                isAutorepeat: event.getIntegerValueField(.keyboardEventAutorepeat) != 0,
                isSynthetic: isSynthetic(event)
            )
        case .keyUp:
            input = .keyUp(keyCode: keyCode(of: event), isSynthetic: isSynthetic(event))
        default:
            return Unmanaged.passUnretained(event)
        }

        let decision = machine.handle(input)
        apply(decision.effects)
        return decision.passesThrough ? Unmanaged.passUnretained(event) : nil
    }

    private func apply(_ effects: [HoldKeyStateMachine.Effect]) {
        for effect in effects {
            switch effect {
            case .reEnableTap:
                if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            case .startHoldTimer:
                startHoldTimer()
            case .cancelHoldTimer:
                cancelHoldTimer()
            case .replayShortPress:
                replayShortPress()
            case .emit(let hotkeyEvent):
                continuation?.yield(hotkeyEvent)
            }
        }
    }

    private func keyCode(of event: CGEvent) -> UInt16 {
        UInt16(truncatingIfNeeded: event.getIntegerValueField(.keyboardEventKeycode))
    }

    private func isSynthetic(_ event: CGEvent) -> Bool {
        event.getIntegerValueField(.eventSourceUserData) == Self.syntheticMarker
    }

    private func startHoldTimer() {
        cancelHoldTimer()
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + machine.holdThreshold.timeInterval)
        timer.setEventHandler { [weak self] in
            guard let self, let effect = self.machine.holdThresholdElapsed() else { return }
            self.apply([effect])
        }
        timer.resume()
        holdTimer = timer
    }

    private func cancelHoldTimer() {
        holdTimer?.cancel()
        holdTimer = nil
    }

    /// Replays the held-back press as a real one.
    ///
    /// Posted at the HID end, not the session: `cgAnnotatedSessionEventTap` places
    /// the event behind all taps, where Raycast, Spotlight or Alfred never see it.
    /// `cghidEventTap` places it at the head of the chain — where our own tap sees
    /// it too, hence the marker.
    private func replayShortPress() {
        guard let source = CGEventSource(stateID: .combinedSessionState) else { return }
        source.userData = Self.syntheticMarker

        var posted = 0
        for isDown in [true, false] {
            guard let event = CGEvent(
                keyboardEventSource: source,
                virtualKey: machine.keyCode,
                keyDown: isDown
            ) else { continue }
            event.setIntegerValueField(.eventSourceUserData, value: Self.syntheticMarker)
            machine.expectReplay()
            posted += 1
            event.post(tap: .cghidEventTap)
        }
        if posted > 0 { scheduleReplayReset() }
    }

    /// In case a replayed event never comes back — otherwise a later real press
    /// counts as ours.
    private func scheduleReplayReset() {
        replayResetTimer?.cancel()
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + 0.25)
        timer.setEventHandler { [weak self] in
            self?.machine.replayResetElapsed()
        }
        timer.resume()
        replayResetTimer = timer
    }
}
