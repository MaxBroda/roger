import Foundation

/// A macOS audio input device that Roger can capture from.
///
/// Identified by ``uid`` (stable across launches and reboots — the CoreAudio
/// device ID changes) and enriched with ``transport`` so the UI can warn about
/// Bluetooth devices that will force AirPods-style HFP switching.
public struct InputDevice: Equatable, Sendable, Identifiable {
    public enum Transport: Sendable, Equatable {
        case builtIn
        case wired          // USB, Thunderbolt, 3.5 mm jack
        case bluetooth      // AirPods, BT headsets — HFP-Codec-Switch penalty
        case continuity     // iPhone / iPad / Apple Watch mic via Continuity
        case aggregate      // Aggregate / Multi-Output — no single transport
        case virtual        // Loopback, Screen Sharing, BlackHole …
        case unknown
    }

    /// Stable identifier: CoreAudio's device UID. Persist this, not the numeric
    /// AudioDeviceID which can change between reboots or device reconnects.
    public let uid: String
    public let name: String
    public let transport: Transport
    /// The current numeric CoreAudio device ID. Only valid within the current
    /// process — do not persist. Rediscovered on every enumeration.
    public let audioDeviceID: UInt32

    public var id: String { uid }

    public init(uid: String, name: String, transport: Transport, audioDeviceID: UInt32) {
        self.uid = uid
        self.name = name
        self.transport = transport
        self.audioDeviceID = audioDeviceID
    }

    /// Bluetooth devices force AirPods into HFP mono, sacrificing audio playback
    /// quality and adding ~1 s of codec-switch latency at recording start. The
    /// UI marks these so users can pick built-in when both are available.
    public var isRecommendedForDictation: Bool {
        switch transport {
        case .builtIn, .wired: return true
        case .bluetooth, .continuity, .aggregate, .virtual, .unknown: return false
        }
    }
}
