import Foundation

// MARK: - File Manager

struct ModelFileManager {
    private let modelsDirectory: URL

    init(modelsDirectory: URL) {
        self.modelsDirectory = modelsDirectory
    }

    func localURL(for modelID: String) -> URL {
        modelsDirectory.appendingPathComponent(modelID)
    }

    func isDownloaded(_ modelID: String) -> Bool {
        FileManager.default.fileExists(atPath: localURL(for: modelID).path)
    }

    func downloadedIDs() -> [String] {
        guard let enumerator = FileManager.default.enumerator(
            at: modelsDirectory,
            includingPropertiesForKeys: nil,
            options: [.skipsSubdirectoryDescendants, .skipsHiddenFiles]
        ) else { return [] }
        return enumerator.compactMap { ($0 as? URL)?.lastPathComponent }
    }

    func delete(_ modelID: String) throws {
        let url = localURL(for: modelID)
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }

    func totalDiskUsage() -> UInt64 {
        guard let enumerator = FileManager.default.enumerator(
            at: modelsDirectory,
            includingPropertiesForKeys: nil,
            options: [.skipsSubdirectoryDescendants, .skipsHiddenFiles]
        ) else { return 0 }
        var total: UInt64 = 0
        for case let url as URL in enumerator {
            if let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
               let size = attrs[.size] as? UInt64
            {
                total += size
            }
        }
        return total
    }
}

// MARK: - Download Manager

private actor TaskRegistry {
    var map: [Int: (modelID: String, continuation: CheckedContinuation<URL, Error>)] = [:]

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

@MainActor
final class ModelDownloadManager: NSObject {
    private let registry = TaskRegistry()
    private let fileManager: ModelFileManager

    private lazy var session: URLSession = .init(configuration: .default, delegate: self, delegateQueue: nil)

    private(set) var progress: [String: Double] = [:]
    private(set) var failures: [String: String] = [:]

    init(fileManager: ModelFileManager) {
        self.fileManager = fileManager
        super.init()
    }

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

    func cancelDownload(id: String) {
        progress.removeValue(forKey: id)
        failures.removeValue(forKey: id)
    }
}

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
