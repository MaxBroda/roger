import Foundation
import Observation

/// Owns the dictionary: holds it in memory, writes it to disk and reads it back
/// when the file changes from outside. On the MainActor, because every change
/// comes from a user action.
@MainActor
@Observable
public final class DictionaryStore {
    public private(set) var dictionary: PhraseDictionary

    /// Kept around because every rule carries a compiled regular expression.
    public private(set) var rules: [RewriteRule]

    /// The context list for recognition hangs off this.
    public var onChange: ((PhraseDictionary) -> Void)?

    public let fileURL: URL

    private let file: JSONFile<[DictionaryEntry]>
    private var watcher: DirectoryWatcher?
    private var lastWrittenAt: Date?

    public init(fileURL: URL = AppFiles.dictionary, seed: [DictionaryEntry] = DictionarySeed.entries) {
        self.fileURL = fileURL
        self.file = JSONFile(url: fileURL)

        // On first launch the sample dictionary lands on disk as a file —
        // findable and disposable instead of a default that haunts.
        let loaded = (try? file.read()) ?? nil
        let initial = PhraseDictionary(entries: loaded ?? seed)
        self.dictionary = initial
        self.rules = initial.rules

        if loaded == nil { persist() }
        startWatching()
    }

    public func upsert(_ entry: DictionaryEntry) {
        dictionary.upsert(entry)
        commit()
    }

    public func remove(id: UUID) {
        dictionary.remove(id: id)
        commit()
    }

    public func setEnabled(_ isEnabled: Bool, for id: UUID) {
        guard let entry = dictionary.entry(id: id),
              let updated = entry.with(isEnabled: isEnabled)
        else { return }
        upsert(updated)
    }

    public func resetToSeed() {
        dictionary = PhraseDictionary(entries: DictionarySeed.entries)
        commit()
    }

    /// Re-reads the file and discards what was in memory — editing the dictionary
    /// in an editor shows up in the window without a relaunch.
    public func reloadFromDisk() {
        guard let entries = ((try? file.read()) ?? nil) else { return }
        let reloaded = PhraseDictionary(entries: entries)
        guard reloaded != dictionary else { return }
        dictionary = reloaded
        rules = reloaded.rules
        onChange?(reloaded)
    }

    private func commit() {
        rules = dictionary.rules
        persist()
        onChange?(dictionary)
    }

    private func persist() {
        try? file.write(dictionary.entries)
        // The watcher reports our own write too — without this mark every change
        // would drag a pointless reload behind it.
        lastWrittenAt = file.modificationDate
    }

    private func startWatching() {
        watcher = DirectoryWatcher(url: fileURL.deletingLastPathComponent()) { [weak self] in
            guard let self else { return }
            let current = self.file.modificationDate
            guard current != self.lastWrittenAt else { return }
            self.lastWrittenAt = current
            self.reloadFromDisk()
        }
    }
}
