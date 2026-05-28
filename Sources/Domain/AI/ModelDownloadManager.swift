import Foundation

// MARK: - ModelFileManager

/// Manages on-disk storage and enumeration of downloaded AI model files.
struct ModelFileManager {
    /// The directory where model files are stored.
    private let modelsDirectory: URL

    /// Creates a file manager rooted at the given models directory.
    init(modelsDirectory: URL) {
        self.modelsDirectory = modelsDirectory
    }

    /// Returns the on-disk URL for a given model ID.
    func localURL(for modelID: String) -> URL {
        modelsDirectory.appendingPathComponent(modelID)
    }

    /// Checks whether a model file exists on disk.
    func isDownloaded(_ modelID: String) -> Bool {
        FileManager.default.fileExists(atPath: localURL(for: modelID).path)
    }

    /// Lists all downloaded model IDs by enumerating the models directory.
    func downloadedIDs() -> [String] {
        guard let enumerator = FileManager.default.enumerator(
            at: modelsDirectory,
            includingPropertiesForKeys: nil,
            options: [.skipsSubdirectoryDescendants, .skipsHiddenFiles]
        ) else { return [] }
        return enumerator.compactMap { ($0 as? URL)?.lastPathComponent }
    }

    /// Deletes a downloaded model file from disk.
    func delete(_ modelID: String) throws {
        let url = localURL(for: modelID)
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }

    /// Calculates the total disk usage of all downloaded model files in bytes.
    func totalDiskUsage() -> UInt64 {
        guard let enumerator = FileManager.default.enumerator(
            at: modelsDirectory,
            includingPropertiesForKeys: nil,
            options: [.skipsSubdirectoryDescendants, .skipsHiddenFiles]
        ) else { return 0 }
        var total: UInt64 = 0
        for case let url as URL in enumerator {
            if let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
               let size = attrs[.size] as? UInt64 {
                total += size
            }
        }
        return total
    }
}

// MARK: - TaskRegistry

/// An actor that maps URLSession task identifiers to their associated model
/// IDs and Swift continuations for async/await bridging.
private actor TaskRegistry {
    /// Internal storage mapping task identifiers to model ID + continuation pairs.
    var map: [Int: (modelID: String, continuation: CheckedContinuation<URL, Error>)] = [:]

    /// Registers a download task's continuation for later resumption.
    func register(taskID: Int, modelID: String, continuation: CheckedContinuation<URL, Error>) {
        map[taskID] = (modelID, continuation)
    }

    func lookup(_ taskID: Int) -> (modelID: String, continuation: CheckedContinuation<URL, Error>)? {
        map[taskID]
    }

    func unregister(_ taskID: Int) {
        map.removeValue(forKey: taskID)
    }

    func isRegistered(_ taskID: Int) -> Bool {
        map[taskID] != nil
    }
}

/// Manages the actual HTTP download of model files using URLSession download
/// tasks with progress tracking and failure reporting.
@MainActor
final class ModelDownloadManager: NSObject {
    /// Registry for bridging URLSession delegates to Swift concurrency.
    private let registry = TaskRegistry()
    /// File manager for on-disk model storage.
    private let fileManager: ModelFileManager

    /// The URLSession used for model downloads, configured lazily.
    private lazy var session: URLSession = .init(configuration: .default, delegate: self, delegateQueue: nil)

    /// Current download progress for each model ID (0.0–1.0).
    private(set) var progress: [String: Double] = [:]
    /// Failure messages keyed by model ID.
    private(set) var failures: [String: String] = [:]

    /// Creates the download manager with the given file manager.
    init(fileManager: ModelFileManager) {
        self.fileManager = fileManager
        super.init()
    }

    /// Begins downloading a model file from the given URL.
    /// - Parameters:
    ///   - id: The model identifier for tracking.
    ///   - url: The remote URL to download from.
    /// - Returns: The local file URL of the downloaded model.
    func downloadModel(id: String, from url: URL) async throws -> URL {
        let task = session.downloadTask(with: url)
        failures.removeValue(forKey: id)
        return try await withCheckedThrowingContinuation { continuation in
            Task {
                await registry.register(taskID: task.taskIdentifier, modelID: id, continuation: continuation)
                progress[id] = 0
                task.resume()
            }
        }
    }

    /// Cancels tracking for a download (clears progress and failures for the ID).
    /// Does not cancel the underlying URLSession task.
    func cancelDownload(id: String) {
        progress.removeValue(forKey: id)
        failures.removeValue(forKey: id)
    }
}

// MARK: - URLSessionDownloadDelegate

extension ModelDownloadManager: URLSessionDownloadDelegate {
    nonisolated func urlSession(
        _: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData _: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        let p = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
        Task {
            guard let entry = await registry.lookup(downloadTask.taskIdentifier) else { return }
            await MainActor.run { progress[entry.modelID] = p }
        }
    }

    nonisolated func urlSession(
        _: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        Task {
            guard let entry = await registry.lookup(downloadTask.taskIdentifier) else { return }
            let dest = fileManager.localURL(for: entry.modelID)
            let parent = dest.deletingLastPathComponent()
            try? FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
            do {
                try? FileManager.default.removeItem(at: dest)
                try FileManager.default.moveItem(at: location, to: dest)
                await MainActor.run { progress[entry.modelID] = 1.0 }
                entry.continuation.resume(returning: dest)
                await registry.unregister(downloadTask.taskIdentifier)
            } catch {
                entry.continuation.resume(throwing: error)
                await registry.unregister(downloadTask.taskIdentifier)
            }
        }
    }

    nonisolated func urlSession(
        _: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        guard let error else { return }
        Task {
            guard let entry = await registry.lookup(task.taskIdentifier) else { return }
            let msg = error.localizedDescription
            await MainActor.run {
                progress.removeValue(forKey: entry.modelID)
                failures[entry.modelID] = msg
            }
            entry.continuation.resume(throwing: error)
            await registry.unregister(task.taskIdentifier)
        }
    }
}
