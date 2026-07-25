import CryptoKit
import Foundation

// MARK: - LiveAIService

/// The production on-device AI service that manages model downloads, catalog
/// loading, and inference via the local `InferenceEngine`.
@MainActor
class LiveAIService: ObservableObject {
    /// Maps model IDs to their current download state (notDownloaded, downloading, ready, failed).
    @Published var downloadStates: [String: ModelDownloadState] = [:]
    private var _catalog: [ModelBundle] = []
    private let downloadManager: ModelDownloadManager
    private let fileManager: ModelFileManager
    private let engine = InferenceEngine()

    /// Creates the service, setting up a models directory within
    /// Application Support and configuring the download/file managers.
    init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        var modelsDir = support.appendingPathComponent("com.ajung.RULYX/models", isDirectory: true)
        try? FileManager.default.createDirectory(at: modelsDir, withIntermediateDirectories: true)
        var resourceValues = URLResourceValues()
        resourceValues.isExcludedFromBackup = true
        try? modelsDir.setResourceValues(resourceValues)
        fileManager = ModelFileManager(modelsDirectory: modelsDir)
        downloadManager = ModelDownloadManager(fileManager: fileManager)
    }

    private static let defaultCatalog: [ModelBundle] = [
        ModelBundle(
            id: "phi-3-mini-q4",
            name: "Phi-3 Mini (Q4)",
            role: .textGenerator,
            downloadURL: URL(string: "https://huggingface.co/microsoft/Phi-3-mini-4k-instruct-gguf/resolve/main/Phi-3-mini-4k-instruct-q4.gguf")!,
            fileSize: 2_393_231_072,
            description: "Microsoft Phi-3 mini 3.8B parameter model, 4-bit quantized.",
            requires: "17.0",
            sha256: "8a83c7fb9049a9b2e92266fa7ad04933bb53aa1e85136b7b30f1b8000ff2edef"
        ),
        ModelBundle(
            id: "qwen3-1.7b-q8",
            name: "Qwen3 1.7B (Q8_0)",
            role: .textGenerator,
            downloadURL: URL(string: "https://huggingface.co/Qwen/Qwen3-1.7B-GGUF/resolve/main/Qwen3-1.7B-Q8_0.gguf")!,
            fileSize: 1_834_426_016,
            description: "Official Qwen3 1.7B model, Q8_0 quantized, for on-device moderation and content analysis.",
            requires: "17.0",
            sha256: "061b54daade076b5d3362dac252678d17da8c68f07560be70818cace6590cb1a"
        ),
    ]

    private struct CatalogManifest: Decodable {
        let models: [ModelBundle]
    }

    /// Rebuilds the `downloadStates` dictionary from the download manager's
    /// current progress, failures, and on-disk state.
    func rebuildStates() {
        var states: [String: ModelDownloadState] = [:]
        let failures = downloadManager.failures
        let progress = downloadManager.progress
        for model in _catalog {
            let id = model.id
            if let msg = failures[id] {
                states[id] = .failed(msg)
            } else if let p = progress[id] {
                states[id] = p >= 1.0 ? .ready : .downloading(p)
            } else if fileManager.isDownloaded(id) {
                states[id] = .ready
            } else {
                states[id] = .notDownloaded
            }
        }
        downloadStates = states
    }

    /// The current model catalog, fetched asynchronously from the backing store.
    var catalog: [ModelBundle] {
        get async { _catalog }
    }

    /// Reloads the model catalog from the bundled manifest or falls back
    /// to the built-in default catalog.
    func refreshCatalog() async throws {
        _catalog = try Self.loadCatalog()
        rebuildStates()
    }

    /// Downloads a model from its remote URL, polling progress until completion.
    /// - Parameter model: The `ModelBundle` describing the model to download.
    func download(_ model: ModelBundle) async throws {
        rebuildStates()

        let box = DownloadBox()
        let downloadTask = Task {
            do {
                let result = try await downloadManager.downloadModel(id: model.id, from: model.downloadURL)
                box.complete()
                return result
            } catch {
                box.fail(error)
                throw error
            }
        }

        while !box.isFinished {
            rebuildStates()
            try await Task.sleep(for: .milliseconds(200))
        }

        rebuildStates()
        if let error = box.error {
            throw error
        }
        _ = try await downloadTask.value

        let local = fileManager.localURL(for: model.id)
        if let attrs = try? FileManager.default.attributesOfItem(atPath: local.path),
           let size = attrs[.size] as? Int64,
           size < model.fileSize / 2
        {
            let error = AIError("Downloaded file (\(ByteCountFormatter().string(fromByteCount: size))) is much smaller than expected (\(ByteCountFormatter().string(fromByteCount: model.fileSize))). The model URL may be incorrect.")
            try? fileManager.delete(model.id)
            downloadManager.recordFailure(id: model.id, message: error.localizedDescription)
            rebuildStates()
            throw error
        }

        // SHA-256 integrity check. A configured hash is MANDATORY for catalog
        // models: downloading a multi-GB executable artifact without integrity
        // verification is a supply-chain risk, so fail closed when it is absent.
        guard let expectedHash = model.sha256, !expectedHash.isEmpty else {
            let error = AIError("Model \(model.id) has no SHA-256 integrity hash configured — refusing to install an unverifiable download.")
            try? fileManager.delete(model.id)
            downloadManager.recordFailure(id: model.id, message: error.localizedDescription)
            rebuildStates()
            throw error
        }
        // Stream the file in chunks — never load a multi-GB model into memory.
        let fileHandle = try FileHandle(forReadingFrom: local)
        var hasher = SHA256()
        while true {
            let chunk = autoreleasepool { fileHandle.readData(ofLength: 8 * 1024 * 1024) }
            if chunk.isEmpty {
                break
            }
            hasher.update(data: chunk)
        }
        try fileHandle.close()
        let actualHash = hasher.finalize().map { String(format: "%02x", $0) }.joined()
        guard actualHash == expectedHash.lowercased() else {
            let error = AIError("Model integrity check failed: SHA-256 mismatch. Expected \(expectedHash), got \(actualHash).")
            try? fileManager.delete(model.id)
            downloadManager.recordFailure(id: model.id, message: error.localizedDescription)
            rebuildStates()
            throw error
        }
        AppLogger.persistence.info("SHA-256 integrity check passed for \(model.id, privacy: .private)")

        rebuildStates()
    }

    /// Cancels an in-progress download and clears its state.
    func cancelDownload(_ modelID: String) {
        downloadManager.cancelDownload(id: modelID)
        rebuildStates()
    }

    /// Returns the total disk usage of all downloaded model files in bytes.
    func totalDiskUsage() -> UInt64 {
        fileManager.totalDiskUsage()
    }

    /// Deletes a downloaded model from disk and clears its download state.
    /// - Parameter modelID: The identifier of the model to remove.
    func delete(_ modelID: String) async throws {
        try fileManager.delete(modelID)
        downloadManager.cancelDownload(id: modelID)
        rebuildStates()
    }

    /// Returns the current download state for a given model ID by checking
    /// failures, progress, and on-disk presence.
    func state(for modelID: String) -> ModelDownloadState {
        if let msg = downloadManager.failures[modelID] {
            return .failed(msg)
        }
        if let p = downloadManager.progress[modelID] {
            return p >= 1.0 ? .ready : .downloading(p)
        }
        if fileManager.isDownloaded(modelID) {
            return .ready
        }
        return .notDownloaded
    }

    /// Returns the list of model IDs that are fully downloaded on disk.
    func downloadedModelIDs() -> [String] {
        fileManager.downloadedIDs()
    }

    /// Runs text classification using the local inference engine.
    /// - Parameters:
    ///   - text: The text to classify.
    ///   - modelID: The model identifier (currently unused; classification is local-only).
    func classify(_ text: String, using _: String) async throws -> [String: Double] {
        engine.classify(text: text)
    }

    /// Runs text generation / completion using the local inference engine.
    /// - Parameters:
    ///   - prompt: The input prompt text.
    ///   - modelID: The model identifier (currently unused; uses local engine).
    /// - Returns: An async stream yielding tokens as they are produced.
    func complete(prompt: String, using _: String) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
                let analysis = self.engine.analyze(text: prompt)
                let words = analysis.components(separatedBy: .newlines)
                for (i, word) in words.enumerated() {
                    continuation.yield(word + (i < words.count - 1 ? "\n" : ""))
                    try await Task.sleep(for: .milliseconds(150))
                }
                continuation.finish()
            }
        }
    }

    /// Loads the model catalog, attempting the bundled manifest first and
    /// falling back to the built-in default catalog on failure.
    static func loadCatalog() throws -> [ModelBundle] {
        do {
            return try loadCatalogFromBundle()
        } catch {
            AppLogger.persistence.error("Falling back to built-in AI catalog: \(error.localizedDescription, privacy: .private)")
            return defaultCatalog
        }
    }

    /// Attempts to load the model manifest from the app bundle's JSON files.
    private static func loadCatalogFromBundle(bundle: Bundle = .main) throws -> [ModelBundle] {
        let candidateURLs = [
            bundle.url(forResource: "model_manifest", withExtension: "json"),
            bundle.url(forResource: "model_manifest", withExtension: "json", subdirectory: "AI"),
        ].compactMap(\.self)

        guard let url = candidateURLs.first else {
            throw AIError("Missing bundled model_manifest.json")
        }

        let data = try Data(contentsOf: url)
        let manifest = try JSONDecoder().decode(CatalogManifest.self, from: data)
        return manifest.models
    }
}

// MARK: - OnDeviceAIService Conformance

extension LiveAIService: OnDeviceAIService {}

// MARK: - DownloadBox

/// A simple synchronization helper that tracks whether an async download
/// has finished and whether it completed with an error.
@MainActor
private class DownloadBox {
    private(set) var isFinished = false
    private(set) var error: Error?

    func complete() {
        isFinished = true
    }

    func fail(_ error: Error) {
        self.error = error
        isFinished = true
    }
}
