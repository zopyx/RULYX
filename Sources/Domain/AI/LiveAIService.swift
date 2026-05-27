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
            fileSize: 2_350_000_000,
            description: "Microsoft Phi-3 mini 3.8B parameter model, 4-bit quantized.",
            requires: "17.0"
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
        rebuildStates()
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
            AppLogger.persistence.error("Falling back to built-in AI catalog: \(error.localizedDescription, privacy: .public)")
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
