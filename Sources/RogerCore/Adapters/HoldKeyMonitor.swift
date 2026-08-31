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

    private var binding: HotkeyBinding

    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    /// Keeps the monitor alive as long as the tap carries it as `userInfo` —
    /// otherwise the callback would point at freed memory.
    private var tapContext: Unmanaged<HoldKeyMonitor>?
    private var continuation: AsyncStream<HotkeyEvent>.Continuation?
    private var holdTimer: DispatchSourceTimer?

    private var isKeyDown = false
    private var isDictating = false
    private var pendingReplays = 0
    private var replayResetTimer: DispatchSourceTimer?

    public init(binding: HotkeyBinding = .escHold) {
        self.binding = binding
    }

    /// Binds a different key. The tap stays up — it listens to all keys anyway,
    /// and rebuilding it would only trigger the TCC check again.
    public func rebind(to newBinding: HotkeyBinding) {
        guard newBinding != binding else { return }
        cancelHoldTimer()
        isKeyDown = false
        isDictating = false
        binding = newBinding
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
        pendingReplays = 0
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
        isKeyDown = false
        isDictating = false
        continuation?.finish()
        continuation = nil
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        // When the system disables the tap, every event during the stall is lost —
        // a keyUp included. Give up the state instead of staying open forever.
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            resetAfterInterruption()
            return Unmanaged.passUnretained(event)
        }

        let keyCode = UInt16(truncatingIfNeeded: event.getIntegerValueField(.keyboardEventKeycode))
        guard keyCode == binding.keyCode else { return Unmanaged.passUnretained(event) }

        // Let our own replayed events through. The counter is the belt in case the
        // marker gets lost — otherwise it loops forever.
        if event.getIntegerValueField(.eventSourceUserData) == Self.syntheticMarker
            || pendingReplays > 0 {
            pendingReplays = max(0, pendingReplays - 1)
            return Unmanaged.passUnretained(event)
        }

        switch type {
        case .keyDown:
            let isAutorepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
            if !isAutorepeat, !isKeyDown {
                isKeyDown = true
                startHoldTimer()
            }
            return nil

        case .keyUp:
            isKeyDown = false
            cancelHoldTimer()
            if isDictating {
                isDictating = false
                continuation?.yield(.pressEnded)
            } else if binding.replaysShortPress {
                replayShortPress()
            }
            return nil

        default:
            return Unmanaged.passUnretained(event)
        }
    }

    /// Cleans up after the tap was disabled: a recording whose keyUp was lost in
    /// the gap would never end.
    private func resetAfterInterruption() {
        cancelHoldTimer()
        isKeyDown = false
        pendingReplays = 0
        if isDictating {
            isDictating = false
            continuation?.yield(.pressEnded)
        }
    }

    private func startHoldTimer() {
        cancelHoldTimer()
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + binding.holdThreshold.timeInterval)
        timer.setEventHandler { [weak self] in
            guard let self, self.isKeyDown, !self.isDictating else { return }
            self.isDictating = true
            self.continuation?.yield(.pressBegan)
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
                virtualKey: binding.keyCode,
                keyDown: isDown
            ) else { continue }
            event.setIntegerValueField(.eventSourceUserData, value: Self.syntheticMarker)
            pendingReplays += 1
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
            self?.pendingReplays = 0
        }
        timer.resume()
        replayResetTimer = timer
    }
}
