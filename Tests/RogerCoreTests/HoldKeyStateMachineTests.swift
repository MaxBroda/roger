import Testing

@testable import RogerCore

/// The two bugs that actually bit in daily use (#1, #2) both lived in the hold
/// key state machine, and both were fixed without a test. They only showed up
/// after minutes of idling — which is why they are pinned down here instead of
/// by hand.
struct HoldKeyStateMachineTests {
    private let esc = HotkeyBinding.escHold
    private let f13 = HotkeyBinding(
        keyCode: 105, holdThreshold: .milliseconds(220), replaysShortPress: false
    )

    private func machineHoldingEsc() -> HoldKeyStateMachine {
        var machine = HoldKeyStateMachine(binding: esc)
        _ = machine.handle(.keyDown(keyCode: esc.keyCode, isAutorepeat: false, isSynthetic: false))
        #expect(machine.holdThresholdElapsed() == .emit(.pressBegan))
        return machine
    }

    // MARK: - #2: tap disabled between keyDown and keyUp

    @Test func beendetDasDiktatWennDerTapMittenImDruckAusfällt() {
        var machine = machineHoldingEsc()

        let interrupted = machine.handle(.tapDisabled)
        #expect(interrupted.effects.contains(.reEnableTap))
        #expect(interrupted.effects.contains(.emit(.pressEnded)))
        #expect(machine.isDictating == false)
        #expect(machine.isKeyDown == false)
    }

    @Test func liestDasVerspäteteKeyUpNichtAlsNeuenDruck() {
        var machine = machineHoldingEsc()
        _ = machine.handle(.tapDisabled)

        // The keyUp of the long-released key arrives after the tap is back.
        let stale = machine.handle(.keyUp(keyCode: esc.keyCode, isSynthetic: false))
        #expect(!stale.effects.contains(.emit(.pressEnded)))
        #expect(machine.isKeyDown == false)

        // And the next real press starts a dictation again.
        _ = machine.handle(.keyDown(keyCode: esc.keyCode, isAutorepeat: false, isSynthetic: false))
        #expect(machine.holdThresholdElapsed() == .emit(.pressBegan))
    }

    // MARK: - Short press

    @Test func spieltEinenKurzenDruckGenauEinmalNach() {
        var machine = HoldKeyStateMachine(binding: esc)

        let down = machine.handle(
            .keyDown(keyCode: esc.keyCode, isAutorepeat: false, isSynthetic: false)
        )
        #expect(down.passesThrough == false)
        #expect(down.effects == [.startHoldTimer])

        // Released before the threshold: no dictation, the press is replayed.
        let up = machine.handle(.keyUp(keyCode: esc.keyCode, isSynthetic: false))
        #expect(up.passesThrough == false)
        #expect(up.effects == [.cancelHoldTimer, .replayShortPress])

        machine.expectReplay()
        machine.expectReplay()

        // The replayed pair comes back through the tap and passes without being
        // read as a fresh press — otherwise it loops forever.
        let replayDown = machine.handle(
            .keyDown(keyCode: esc.keyCode, isAutorepeat: false, isSynthetic: true)
        )
        let replayUp = machine.handle(.keyUp(keyCode: esc.keyCode, isSynthetic: true))
        #expect(replayDown == .pass)
        #expect(replayUp == .pass)
        #expect(machine.isKeyDown == false)
        #expect(machine.pendingReplays == 0)
    }

    @Test func startetDenHalteTimerNichtBeiTastenwiederholung() {
        var machine = HoldKeyStateMachine(binding: esc)
        _ = machine.handle(.keyDown(keyCode: esc.keyCode, isAutorepeat: false, isSynthetic: false))

        let repeated = machine.handle(
            .keyDown(keyCode: esc.keyCode, isAutorepeat: true, isSynthetic: false)
        )
        #expect(repeated.effects.isEmpty)
    }

    @Test func lässtFremdeTastenDurch() {
        var machine = HoldKeyStateMachine(binding: esc)
        let other = machine.handle(.keyDown(keyCode: 40, isAutorepeat: false, isSynthetic: false))
        #expect(other == .pass)
        #expect(machine.isKeyDown == false)
    }

    // MARK: - Replays that never come back

    @Test func schlucktNachDemResetKeinenEchtenDruckMehr() {
        var machine = HoldKeyStateMachine(binding: esc)
        machine.expectReplay()
        machine.expectReplay()

        // Both replayed events are lost on the way back.
        machine.replayResetElapsed()
        #expect(machine.pendingReplays == 0)

        let down = machine.handle(
            .keyDown(keyCode: esc.keyCode, isAutorepeat: false, isSynthetic: false)
        )
        #expect(down.passesThrough == false)
        #expect(down.effects == [.startHoldTimer])
    }

    @Test func zähltDenGürtelHerunterWennDieMarkierungVerlorenGeht() {
        var machine = HoldKeyStateMachine(binding: esc)
        machine.expectReplay()

        let unmarked = machine.handle(
            .keyDown(keyCode: esc.keyCode, isAutorepeat: false, isSynthetic: false)
        )
        #expect(unmarked == .pass)
        #expect(machine.pendingReplays == 0)
        #expect(machine.isKeyDown == false)
    }

    // MARK: - Rebind

    @Test func beendetDasDiktatBeimUmbindenWährendDieTasteGehaltenWird() {
        var machine = machineHoldingEsc()

        let effects = machine.rebind(to: f13)
        #expect(effects.contains(.emit(.pressEnded)))
        #expect(effects.contains(.cancelHoldTimer))
        #expect(machine.isDictating == false)
        #expect(machine.isKeyDown == false)
    }

    @Test func hörtNachDemUmbindenAufDieNeueTaste() {
        var machine = machineHoldingEsc()
        _ = machine.rebind(to: f13)

        #expect(machine.handle(
            .keyDown(keyCode: esc.keyCode, isAutorepeat: false, isSynthetic: false)
        ) == .pass)

        _ = machine.handle(.keyDown(keyCode: f13.keyCode, isAutorepeat: false, isSynthetic: false))
        #expect(machine.holdThresholdElapsed() == .emit(.pressBegan))
    }

    @Test func rührtSichNichtWennDieBindungDieselbeBleibt() {
        var machine = machineHoldingEsc()
        #expect(machine.rebind(to: .escHold).isEmpty)
        #expect(machine.isDictating)
    }

    @Test func spieltOhneReplayFlagNichtsNach() {
        var machine = HoldKeyStateMachine(binding: f13)
        _ = machine.handle(.keyDown(keyCode: f13.keyCode, isAutorepeat: false, isSynthetic: false))

        let up = machine.handle(.keyUp(keyCode: f13.keyCode, isSynthetic: false))
        #expect(up.effects == [.cancelHoldTimer])
    }

    // MARK: - Hold threshold

    @Test func meldetDenDruckbeginnNurEinmal() {
        var machine = machineHoldingEsc()
        #expect(machine.holdThresholdElapsed() == nil)
    }

    @Test func meldetKeinenDruckbeginnNachDemLoslassen() {
        var machine = HoldKeyStateMachine(binding: esc)
        _ = machine.handle(.keyDown(keyCode: esc.keyCode, isAutorepeat: false, isSynthetic: false))
        _ = machine.handle(.keyUp(keyCode: esc.keyCode, isSynthetic: false))

        // The timer fired late, after the key was already released.
        #expect(machine.holdThresholdElapsed() == nil)
    }
}
