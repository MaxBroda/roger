public enum HotkeyEvent: Sendable {
    case pressBegan
    case pressEnded
}

/// Watches the push-to-talk key.
///
/// Deliberately *not* `@MainActor`: the tap callback is plain C without a Swift
/// task underneath, and jumping into an actor-isolated method crashed Roger
/// reproducibly. Implementations keep their state on the main thread themselves.
public protocol HotkeyMonitoring: AnyObject, Sendable {
    func start() throws -> AsyncStream<HotkeyEvent>
    func stop()
}
