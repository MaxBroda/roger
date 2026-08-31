import Observation
import RogerCore
import SwiftUI

/// Drives the setup window: polls permission state, triggers the system prompts
/// and knows when a relaunch is due.
@MainActor
@Observable
final class OnboardingModel {
    enum Requirement: CaseIterable, Identifiable {
        case microphone
        case accessibility

        var id: Self { self }

        var title: String {
            switch self {
            case .microphone: "Mikrofon"
            case .accessibility: "Bedienungshilfen"
            }
        }

        var explanation: String {
            switch self {
            case .microphone: "Damit Roger dein Diktat aufnehmen kann."
            case .accessibility: "Damit Roger Esc abfangen und den Text einfügen kann."
            }
        }

        var symbolName: String {
            switch self {
            case .microphone: "mic"
            case .accessibility: "text.cursor"
            }
        }

        var settingsPane: Permissions.SettingsPane {
            switch self {
            case .microphone: .microphone
            case .accessibility: .accessibility
            }
        }
    }

    private(set) var snapshot = Permissions.snapshot()
    /// True once a permission was granted during this session.
    private(set) var needsRelaunch = false

    private var pollTask: Task<Void, Never>?

    func status(of requirement: Requirement) -> PermissionStatus {
        switch requirement {
        case .microphone: snapshot.microphone
        case .accessibility: snapshot.accessibility
        }
    }

    /// System Settings does not report a toggle being flipped — so poll while the
    /// window is open.
    func startPolling() {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                self?.refresh()
                try? await Task.sleep(for: .milliseconds(700))
            }
        }
    }

    func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
    }

    func refresh() {
        let latest = Permissions.snapshot()
        guard latest != snapshot else { return }
        // Only if something was *added*: the event tap already exists and will not
        // see newly permitted keyboard events.
        if !snapshot.isComplete, latest.isComplete || gainedSomething(from: snapshot, to: latest) {
            needsRelaunch = true
        }
        snapshot = latest
    }

    func request(_ requirement: Requirement) {
        switch status(of: requirement) {
        case .notDetermined:
            prompt(requirement)
        case .denied, .granted:
            // Once answered, macOS shows no dialog again — only System Settings
            // is left.
            Permissions.openSettings(for: requirement.settingsPane)
        }
    }

    private func prompt(_ requirement: Requirement) {
        switch requirement {
        case .microphone:
            Task { await Permissions.requestMicrophone(); refresh() }
        case .accessibility:
            Permissions.requestAccessibility()
            refresh()
        }
    }

    /// Relaunches Roger — the new instance comes up before this one goes away.
    func relaunch() {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(
            at: Bundle.main.bundleURL,
            configuration: configuration
        ) { _, _ in
            Task { @MainActor in NSApp.terminate(nil) }
        }
    }

    private func gainedSomething(from old: PermissionsSnapshot, to new: PermissionsSnapshot) -> Bool {
        (!old.microphone.isGranted && new.microphone.isGranted)
            || (!old.accessibility.isGranted && new.accessibility.isGranted)
    }
}
