import Foundation

/// `~/Library/Application Support/Roger/` rather than `UserDefaults`: the
/// dictionary should be editable in a text editor, and defaults get cached —
/// values changed from outside would arrive unreliably.
public enum AppFiles {
    public static var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first ?? URL(fileURLWithPath: NSHomeDirectory()).appending(path: "Library/Application Support")
        let directory = base.appending(path: "Roger", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    public static var dictionary: URL { directory.appending(path: "dictionary.json") }
    public static var history: URL { directory.appending(path: "history.json") }
}

/// A JSON file a human may touch: indented, sorted keys, ISO dates. The sorting
/// also keeps `git diff` quiet.
public struct JSONFile<Payload: Codable & Sendable>: Sendable {
    public let url: URL

    public init(url: URL) {
        self.url = url
    }

    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    public func read() throws -> Payload? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try Self.decoder.decode(Payload.self, from: Data(contentsOf: url))
    }

    public func write(_ payload: Payload) throws {
        try Self.encoder.encode(payload).write(to: url, options: .atomic)
    }

    /// Tells whether a watcher notification concerns us at all.
    public var modificationDate: Date? {
        try? FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate] as? Date
    }
}
