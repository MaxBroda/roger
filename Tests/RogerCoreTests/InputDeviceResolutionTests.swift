import Testing

@testable import RogerCore

/// The promise of the microphone setting is a negative one: no dictation on a
/// Bluetooth microphone unless it was asked for. That promise broke silently
/// once, because an absent pinned device fell back to the system default — which
/// with a headset connected *is* the headset.
struct InputDeviceResolutionTests {
    private let builtIn = InputDevice(
        uid: "BuiltInMicrophoneDevice", name: "MacBook Pro Microphone",
        transport: .builtIn, audioDeviceID: 1
    )
    private let headset = InputDevice(
        uid: "4C-87-5D-0C-0A-B6:input", name: "Bose QuietComfort 35",
        transport: .bluetooth, audioDeviceID: 2
    )
    private let iPhone = InputDevice(
        uid: "2E59DA8F-B490", name: "iPhone Microphone",
        transport: .continuity, audioDeviceID: 3
    )
    /// The one that cost an afternoon: pinned, connected, opens fine, delivers
    /// nothing but digital silence.
    private let loopback = InputDevice(
        uid: "MSLoopbackDriverDevice_UID", name: "Microsoft Teams Audio",
        transport: .virtual, audioDeviceID: 4
    )
    private let aggregate = InputDevice(
        uid: "aggregate-42", name: "Interface + Mikrofon",
        transport: .aggregate, audioDeviceID: 5
    )
    private let absentPin = "AC-90-85-66-50-10:input"

    @Test func nimmtDasGepinnteGerätWennEsDaIst() {
        let resolved = AudioDeviceEnumerator.resolve(
            .explicit(uid: headset.uid),
            available: [builtIn, headset],
            systemDefault: builtIn
        )
        #expect(resolved?.device == headset)
        #expect(resolved?.isSubstitute == false)
    }

    @Test func weichtAufDasEingebauteMikrofonAusStattAufsHeadset() {
        let resolved = AudioDeviceEnumerator.resolve(
            .explicit(uid: absentPin),
            available: [builtIn, headset],
            systemDefault: headset
        )
        #expect(resolved?.device == builtIn)
        #expect(resolved?.isSubstitute == true)
    }

    @Test func nimmtDenSystemStandardNurWennKeinEingebautesExistiert() {
        let resolved = AudioDeviceEnumerator.resolve(
            .explicit(uid: absentPin),
            available: [headset],
            systemDefault: headset
        )
        #expect(resolved?.device == headset)
        #expect(resolved?.isSubstitute == true)
    }

    @Test func haltetDasIPhoneMikrofonNichtFuerEingebaut() {
        let resolved = AudioDeviceEnumerator.resolve(
            .explicit(uid: absentPin),
            available: [iPhone, headset],
            systemDefault: headset
        )
        #expect(resolved?.device != iPhone)
    }

    @Test func folgtBeiAutomatischDemSystemStandard() {
        let resolved = AudioDeviceEnumerator.resolve(
            .automatic,
            available: [builtIn, headset],
            systemDefault: headset
        )
        #expect(resolved?.device == headset)
        #expect(resolved?.isSubstitute == false)
    }

    @Test func istKeinErsatzWennDasEingebauteGewaehltUndVorhandenIst() {
        let resolved = AudioDeviceEnumerator.resolve(
            .builtIn,
            available: [builtIn, headset],
            systemDefault: headset
        )
        #expect(resolved?.device == builtIn)
        #expect(resolved?.isSubstitute == false)
    }

    /// A Mac without an internal microphone is not a lost setting — nothing was
    /// pinned, so the system default is the honest answer, not a substitution.
    @Test func istKeinErsatzWennGarKeinEingebautesMikrofonExistiert() {
        let resolved = AudioDeviceEnumerator.resolve(
            .builtIn,
            available: [headset],
            systemDefault: headset
        )
        #expect(resolved?.device == headset)
        #expect(resolved?.isSubstitute == false)
    }

    @Test func liefertNilWennGarKeinGeraetDaIst() {
        #expect(AudioDeviceEnumerator.resolve(.builtIn, available: [], systemDefault: nil) == nil)
        #expect(AudioDeviceEnumerator.resolve(.automatic, available: [], systemDefault: nil) == nil)
        #expect(AudioDeviceEnumerator.resolve(.explicit(uid: absentPin), available: [], systemDefault: nil) == nil)
    }

    @Test func weichtVomGepinntenLoopbackGeraetAufsEingebauteAus() {
        let resolved = AudioDeviceEnumerator.resolve(
            .explicit(uid: loopback.uid),
            available: [builtIn, loopback],
            systemDefault: loopback
        )
        #expect(resolved?.device == builtIn)
        #expect(resolved?.isSubstitute == true)
    }

    @Test func nimmtNichtUeberDenLoopbackSystemStandardAuf() {
        let resolved = AudioDeviceEnumerator.resolve(
            .automatic,
            available: [builtIn, loopback],
            systemDefault: loopback
        )
        #expect(resolved?.device == builtIn)
        #expect(resolved?.isSubstitute == true)
    }

    @Test func weichtBeiAutomatischOhneEingebautesVomLoopbackAufExternesMikroAus() {
        let resolved = AudioDeviceEnumerator.resolve(
            .automatic,
            available: [loopback, headset],
            systemDefault: loopback
        )
        #expect(resolved?.device == headset)
        #expect(resolved?.isSubstitute == true)
    }

    @Test func haeltAggregatGeraeteFuerBrauchbar() {
        let resolved = AudioDeviceEnumerator.resolve(
            .explicit(uid: aggregate.uid),
            available: [builtIn, aggregate],
            systemDefault: builtIn
        )
        #expect(resolved?.device == aggregate)
        #expect(resolved?.isSubstitute == false)
    }

    @Test func bietetLoopbackGeraeteNichtZurAuswahlAn() {
        #expect(loopback.canCaptureVoice == false)
        #expect(builtIn.canCaptureVoice)
        #expect(headset.canCaptureVoice)
        #expect(iPhone.canCaptureVoice)
        #expect(aggregate.canCaptureVoice)
    }
}
