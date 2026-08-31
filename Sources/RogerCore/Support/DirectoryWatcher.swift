import Foundation

/// Watches the directory, not the file: text editors save atomically — a watcher
/// on the file descriptor would lose its target and stay silent forever.
public final class DirectoryWatcher {
    private let source: DispatchSourceFileSystemObject

    /// - Parameter onChange: Runs on the MainActor. One save fires several events.
    public init?(url: URL, onChange: @escaping @MainActor () -> Void) {
        let descriptor = open(url.path, O_EVTONLY)
        guard descriptor >= 0 else { return nil }

        source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .rename, .delete],
            queue: .main
        )
        source.setEventHandler {
            MainActor.assumeIsolated(onChange)
        }
        source.setCancelHandler { close(descriptor) }
        source.resume()
    }

    deinit {
        source.cancel()
    }
}
