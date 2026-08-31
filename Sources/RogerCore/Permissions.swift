import AVFoundation
import AppKit
import ApplicationServices
import IOKit.hid

public enum PermissionStatus: Sendable, Equatable, CustomStringConvertible {
    case granted
    case denied
    case notDetermined

    public var isGranted: Bool { self == .granted }

    public var description: String {
        switch self {
        case .granted: "erteilt"
        case .denied: "verweigert"
        case .notDetermined: "noch nicht gefragt"
        }
    }
}

/// What Roger may do — as one value, so the UI need not stitch three queries
/// together.
public struct PermissionsSnapshot: Sendable, Equatable {
    public let microphone: PermissionStatus
    public let inputMonitoring: PermissionStatus
    public let accessibility: PermissionStatus

    /// Input monitoring is deliberately absent: the tap runs with `.defaultTap`,
    /// which accessibility permits. Only `.listenOnly` would need it as well.
    public var isComplete: Bool {
        microphone.isGranted && accessibility.isGranted
    }
}

/// Two are required: microphone and accessibility — the latter covers both
/// directions, intercepting Esc and posting ⌘V. Input monitoring is carried along
/// for diagnostics only. None of this is available in the App Sandbox.
public enum Permissions {
    public static func snapshot() -> PermissionsSnapshot {
        PermissionsSnapshot(
            microphone: microphoneStatus,
            inputMonitoring: inputMonitoringStatus,
            accessibility: accessibilityStatus
        )
    }

    public static var microphoneStatus: PermissionStatus {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: .granted
        case .notDetermined: .notDetermined
        default: .denied
        }
    }

    @discardableResult
    public static func requestMicrophone() async -> Bool {
        await AVCaptureDevice.requestAccess(for: .audio)
    }

    public static var inputMonitoringStatus: PermissionStatus {
        switch IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) {
        case kIOHIDAccessTypeGranted: .granted
        case kIOHIDAccessTypeDenied: .denied
        default: .notDetermined
        }
    }

    public static var accessibilityStatus: PermissionStatus {
        AXIsProcessTrusted() ? .granted : .notDetermined
    }

    /// Shows the system prompt if the permission is still missing.
    @discardableResult
    public static func requestAccessibility() -> Bool {
        // A literal instead of `kAXTrustedCheckOptionPrompt`: the constant is a
        // global `var` and therefore not concurrency-safe under Swift 6.
        let promptKey = "AXTrustedCheckOptionPrompt"
        return AXIsProcessTrustedWithOptions([promptKey: true] as CFDictionary)
    }

    public static func openSettings(for pane: SettingsPane) {
        guard let url = URL(string: pane.urlString) else { return }
        NSWorkspace.shared.open(url)
    }

    public enum SettingsPane: Sendable {
        case accessibility
        case microphone

        var urlString: String {
            let base = "x-apple.systempreferences:com.apple.preference.security?"
            switch self {
            case .accessibility: return base + "Privacy_Accessibility"
            case .microphone: return base + "Privacy_Microphone"
            }
        }
    }
}
