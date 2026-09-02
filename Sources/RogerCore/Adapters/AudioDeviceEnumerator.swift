import CoreAudio
import Foundation

/// Reads the list of usable audio input devices from CoreAudio.
///
/// Kept as a small stateless facade so `MicrophoneCapture` and the settings UI
/// call the same code path. All CoreAudio primitive-buffer handling stays here.
public enum AudioDeviceEnumerator {
    /// Every device that has at least one input stream (i.e. can capture audio).
    /// The list mirrors what macOS shows under System Settings › Sound › Input.
    public static func inputDevices() -> [InputDevice] {
        deviceIDs().compactMap(inputDevice(for:))
    }

    /// The device currently set as macOS's default input.
    public static func systemDefaultInputDevice() -> InputDevice? {
        guard let id = defaultInputDeviceID() else { return nil }
        return inputDevice(for: id)
    }

    /// The device matching a persisted selection. Returns `nil` if the pinned
    /// device is currently unplugged — callers should fall back to
    /// ``systemDefaultInputDevice()`` in that case.
    public static func resolve(_ selection: InputDeviceSelection) -> InputDevice? {
        switch selection {
        case .automatic:
            return systemDefaultInputDevice()
        case .builtIn:
            // Continuity mics (iPhone / iPad / Watch) are reclassified to
            // `.continuity` in `inputDevice(for:)`, so the built-in filter
            // matches only actual Mac microphones.
            return inputDevices().first { $0.transport == .builtIn }
                ?? systemDefaultInputDevice()
        case .explicit(let uid):
            return inputDevices().first { $0.uid == uid }
        }
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
