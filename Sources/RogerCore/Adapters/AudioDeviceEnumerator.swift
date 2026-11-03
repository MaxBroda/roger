import CoreAudio
import Foundation

/// Reads the list of usable audio input devices from CoreAudio.
///
/// Kept as a small stateless facade so `MicrophoneCapture` and the settings UI
/// call the same code path. All CoreAudio primitive-buffer handling stays here.
public enum AudioDeviceEnumerator {
    /// Where sound currently goes, and over which transport. The transport is
    /// how the resume knows a Bluetooth headset is involved and needs the extra
    /// settle time before playback comes back.
    public struct OutputRoute: Equatable, Sendable {
        public let deviceID: AudioDeviceID
        public let transport: InputDevice.Transport
    }

    /// Every device that has at least one input stream (i.e. can capture audio).
    /// The list mirrors what macOS shows under System Settings › Sound › Input,
    /// loopback drivers included — ``dictationDevices()`` is the list to offer.
    public static func inputDevices() -> [InputDevice] {
        deviceIDs().compactMap(inputDevice(for:))
    }

    /// The devices a user may pin: everything a voice can actually reach.
    public static func dictationDevices() -> [InputDevice] {
        inputDevices().filter(\.canCaptureVoice)
    }

    /// The device currently set as macOS's default input.
    public static func systemDefaultInputDevice() -> InputDevice? {
        guard let id = defaultInputDeviceID() else { return nil }
        return inputDevice(for: id)
    }

    /// The device a persisted selection points at, or a substitute when it is
    /// not connected. `nil` only if CoreAudio offers no input device at all.
    public static func resolve(_ selection: InputDeviceSelection) -> ResolvedInputDevice? {
        resolve(selection, available: inputDevices(), systemDefault: systemDefaultInputDevice())
    }

    /// The decision itself, without CoreAudio: which device wins, and whether
    /// that is the user's choice or a stand-in. Separated so the rule that keeps
    /// dictation off Bluetooth microphones is covered by tests rather than by
    /// whichever devices happen to be plugged in.
    public static func resolve(
        _ selection: InputDeviceSelection,
        available: [InputDevice],
        systemDefault: InputDevice?
    ) -> ResolvedInputDevice? {
        switch selection {
        case .automatic:
            // A loopback driver as the *system* input would hand Roger silence
            // through a setting that is not even Roger's.
            if let systemDefault, systemDefault.canCaptureVoice {
                return ResolvedInputDevice(device: systemDefault, isSubstitute: false)
            }
            if let builtIn = builtIn(in: available) {
                return ResolvedInputDevice(device: builtIn, isSubstitute: true)
            }
            // Neither the system default nor a built-in mic can carry a voice —
            // an external mic that is merely not *the* default beats silence.
            if let voiceCapable = available.first(where: \.canCaptureVoice) {
                return ResolvedInputDevice(device: voiceCapable, isSubstitute: true)
            }
            return systemDefault.map { ResolvedInputDevice(device: $0, isSubstitute: false) }
        case .builtIn:
            if let builtIn = builtIn(in: available) {
                return ResolvedInputDevice(device: builtIn, isSubstitute: false)
            }
            // No built-in microphone at all (Mac Pro, external-only setups):
            // the system default is the only choice, not a lost setting —
            // unless it can't carry a voice, then an external mic beats silence.
            if let systemDefault, systemDefault.canCaptureVoice {
                return ResolvedInputDevice(device: systemDefault, isSubstitute: false)
            }
            if let voiceCapable = available.first(where: \.canCaptureVoice) {
                return ResolvedInputDevice(device: voiceCapable, isSubstitute: true)
            }
            return systemDefault.map { ResolvedInputDevice(device: $0, isSubstitute: false) }
        case .explicit(let uid):
            // Connected but unable to carry a voice counts as absent: recording
            // from it is silence, and silence is worse than a substitution.
            if let pinned = available.first(where: { $0.uid == uid }), pinned.canCaptureVoice {
                return ResolvedInputDevice(device: pinned, isSubstitute: false)
            }
            // Built-in before the system default: with a headset connected the
            // system default *is* the headset, so falling back there put the
            // dictation on the very device this setting exists to avoid — and
            // left the headset in hands-free mono afterwards.
            if let builtIn = builtIn(in: available) {
                return ResolvedInputDevice(device: builtIn, isSubstitute: true)
            }
            if let systemDefault, systemDefault.canCaptureVoice {
                return ResolvedInputDevice(device: systemDefault, isSubstitute: true)
            }
            if let voiceCapable = available.first(where: \.canCaptureVoice) {
                return ResolvedInputDevice(device: voiceCapable, isSubstitute: true)
            }
            return systemDefault.map { ResolvedInputDevice(device: $0, isSubstitute: true) }
        }
    }

    /// Continuity mics (iPhone / iPad / Watch) are reclassified to `.continuity`
    /// in ``inputDevice(for:)``, so this matches only actual Mac microphones.
    private static func builtIn(in devices: [InputDevice]) -> InputDevice? {
        devices.first { $0.transport == .builtIn }
    }

    /// The default output device and how it connects. A Bluetooth transport is
    /// the signal that resuming playback must wait for the headset to leave call
    /// mode — a wired or built-in output never switches modes and resumes at once.
    public static func defaultOutputRoute() -> OutputRoute? {
        guard let id = defaultOutputDeviceID() else { return nil }
        return OutputRoute(deviceID: id, transport: transport(for: id))
    }

    /// Whether the default output device is doing IO right now — i.e. something
    /// is actually coming out of it. Instant, with no process spawn, unlike
    /// reading now-playing info: the pause can then go out before a Bluetooth
    /// headset's call-mode switch becomes audible over still-playing music.
    public static func isDefaultOutputRunning() -> Bool {
        guard let id = defaultOutputDeviceID() else { return false }
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var running: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &running) == noErr else {
            return false
        }
        return running != 0
    }

    // MARK: - CoreAudio plumbing

    private static func deviceIDs() -> [AudioDeviceID] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        var status = AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size
        )
        guard status == noErr, size > 0 else { return [] }

        let count = Int(size) / MemoryLayout<AudioDeviceID>.size
        var ids = [AudioDeviceID](repeating: 0, count: count)
        status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size,
            &ids
        )
        return status == noErr ? ids : []
    }

    private static func defaultInputDeviceID() -> AudioDeviceID? {
        var deviceID = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size,
            &deviceID
        )
        return (status == noErr && deviceID != 0) ? deviceID : nil
    }

    private static func defaultOutputDeviceID() -> AudioDeviceID? {
        var deviceID = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size,
            &deviceID
        )
        return (status == noErr && deviceID != 0) ? deviceID : nil
    }

    /// Turns a CoreAudio device ID into an ``InputDevice``, or `nil` when the
    /// device has no input streams (output-only speakers, HDMI displays …).
    private static func inputDevice(for id: AudioDeviceID) -> InputDevice? {
        guard hasInputStreams(id) else { return nil }
        guard let uid = stringProperty(id, selector: kAudioDevicePropertyDeviceUID) else { return nil }
        let name = stringProperty(id, selector: kAudioObjectPropertyName) ?? "Unbekannt"
        let rawTransport = transport(for: id)
        // CoreAudio labels iPhone / iPad / Apple Watch Continuity mics as
        // built-in. Reclassify by name so the UI can show them separately and
        // the `.builtIn` preference does not accidentally pick them.
        let finalTransport: InputDevice.Transport
        if rawTransport == .builtIn && looksLikeContinuityMic(name) {
            finalTransport = .continuity
        } else {
            finalTransport = rawTransport
        }
        return InputDevice(
            uid: uid,
            name: name,
            transport: finalTransport,
            audioDeviceID: id
        )
    }

    private static func looksLikeContinuityMic(_ name: String) -> Bool {
        let lowered = name.lowercased()
        return ["iphone", "ipad", "watch"].contains { lowered.contains($0) }
    }

    private static func hasInputStreams(_ id: AudioDeviceID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(id, &address, 0, nil, &size) == noErr, size > 0 else {
            return false
        }
        let bufferListPointer = UnsafeMutablePointer<AudioBufferList>.allocate(capacity: Int(size))
        defer { bufferListPointer.deallocate() }
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, bufferListPointer) == noErr else {
            return false
        }
        let list = UnsafeMutableAudioBufferListPointer(bufferListPointer)
        return list.contains { $0.mNumberChannels > 0 }
    }

    private static func transport(for id: AudioDeviceID) -> InputDevice.Transport {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyTransportType,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &value) == noErr else {
            return .unknown
        }
        switch value {
        case kAudioDeviceTransportTypeBuiltIn: return .builtIn
        case kAudioDeviceTransportTypeUSB,
             kAudioDeviceTransportTypeFireWire,
             kAudioDeviceTransportTypeThunderbolt,
             kAudioDeviceTransportTypePCI,
             kAudioDeviceTransportTypeDisplayPort,
             kAudioDeviceTransportTypeHDMI:
            return .wired
        case kAudioDeviceTransportTypeBluetooth,
             kAudioDeviceTransportTypeBluetoothLE:
            return .bluetooth
        case kAudioDeviceTransportTypeAggregate:
            return .aggregate
        case kAudioDeviceTransportTypeVirtual,
             kAudioDeviceTransportTypeAirPlay,
             kAudioDeviceTransportTypeAVB:
            return .virtual
        default:
            return .unknown
        }
    }

    private static func stringProperty(
        _ id: AudioDeviceID,
        selector: AudioObjectPropertySelector
    ) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var name: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<CFString?>.size)
        let status = AudioObjectGetPropertyData(id, &address, 0, nil, &size, &name)
        guard status == noErr, let name else { return nil }
        return name.takeRetainedValue() as String
    }
}
