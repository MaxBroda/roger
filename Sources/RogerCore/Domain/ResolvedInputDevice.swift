/// What Roger will actually record from, and whether that is what the user
/// asked for. The distinction exists because a substitution nobody sees is how
/// a dictation ends up on a Bluetooth headset the setting was meant to avoid.
public struct ResolvedInputDevice: Equatable, Sendable {
    public let device: InputDevice
    /// The pinned device is not connected and ``device`` stands in for it. The
    /// preference itself is untouched — the choice comes back when the device does.
    public let isSubstitute: Bool

    public init(device: InputDevice, isSubstitute: Bool) {
        self.device = device
        self.isSubstitute = isSubstitute
    }
}
