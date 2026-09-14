import Foundation
import ServiceManagement

/// Registers Roger to launch at login. `SMAppService` is the source of truth —
/// unlike the other preferences here there is no `UserDefaults` mirror, because
/// the registration itself already answers "is this on".
public struct LoginItemPreference: Sendable {
    public init() {}

    public var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    public func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }
}
