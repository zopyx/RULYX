import Foundation

// MARK: - ProtectedDataStore

/// File-backed replacement for `UserDefaults` `Data` storage, used for
/// sensitive moderation-related payloads (internal lists, audit log,
/// list snapshots, saved searches, engagement snapshots).
///
/// Security properties (production mode):
/// - Files live in `Library/Application Support/com.ajung.RULYX/ProtectedStores/`
///   and are written with `.completeFileProtection` (unreadable while the
///   device is locked — unlike the UserDefaults default protection class).
/// - The store directory is excluded from iCloud and local device backups, so
///   moderation metadata no longer leaks into unencrypted Finder/iTunes backups.
/// - One-time migration: on first read, a legacy `UserDefaults` value under
///   `legacyKey` is moved into the protected file and removed from UserDefaults.
///
/// Isolation seam: when a non-standard `UserDefaults` suite is injected (unit
/// tests), storage stays in that suite, preserving test isolation. Pass an
/// explicit `directory` to test the file-backed path itself.
final class ProtectedDataStore {
    private let fileURL: URL?
    private let legacyKey: String
    private let defaults: UserDefaults
    private let useFileStorage: Bool

    init(name: String, legacyKey: String, defaults: UserDefaults = .standard, directory: URL? = nil) {
        self.legacyKey = legacyKey
        self.defaults = defaults

        if let directory {
            useFileStorage = true
            fileURL = directory.appendingPathComponent("\(name).json")
        } else if defaults === UserDefaults.standard {
            useFileStorage = true
            let storeDirectory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("com.ajung.RULYX/ProtectedStores", isDirectory: true)
            fileURL = storeDirectory.appendingPathComponent("\(name).json")
        } else {
            // Injected isolated suite (unit tests) — keep legacy behavior.
            useFileStorage = false
            fileURL = nil
        }
    }

    /// Reads the stored data, migrating any legacy UserDefaults value first
    /// (file-backed mode only).
    func data() -> Data? {
        guard useFileStorage, let fileURL else {
            return defaults.data(forKey: legacyKey)
        }
        if let fileData = try? Data(contentsOf: fileURL) {
            return fileData
        }
        if let legacy = defaults.data(forKey: legacyKey) {
            set(legacy)
            defaults.removeObject(forKey: legacyKey)
            return legacy
        }
        return nil
    }

    /// Writes data atomically. In file-backed mode, writes with complete file
    /// protection into a backup-excluded directory.
    func set(_ data: Data) {
        guard useFileStorage, let fileURL else {
            defaults.set(data, forKey: legacyKey)
            return
        }
        do {
            var directory = fileURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            var resourceValues = URLResourceValues()
            resourceValues.isExcludedFromBackup = true
            try? directory.setResourceValues(resourceValues)
            try data.write(to: fileURL, options: [.atomic, .completeFileProtection])
        } catch {
            AppLogger.persistence.error("ProtectedDataStore write failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
