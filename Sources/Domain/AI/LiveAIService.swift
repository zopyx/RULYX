import Foundation

@MainActor
class LiveAIService: ObservableObject {
    @Published var downloadStates: [String: ModelDownloadState] = [:]
    private var _catalog: [ModelBundle] = []
    private let downloadManager: ModelDownloadManager
    private let fileManager: ModelFileManager
    private let engine = InferenceEngine()

    init() {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        let modelsDir = caches.appendingPathComponent("com.ajung.RULYX/models", isDirectory: true)
        try? FileManager.default.createDirectory(at: modelsDir, withIntermediateDirectories: true)
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

    var catalog: [ModelBundle] {
        get async { _catalog }
    }

    func refreshCatalog() async throws {
        _catalog = try Self.loadCatalog()
        rebuildStates()
    }

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

    func delete(_ modelID: String) async throws {
        try fileManager.delete(modelID)
        downloadManager.cancelDownload(id: modelID)
        rebuildStates()
    }

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

    func downloadedModelIDs() -> [String] {
        fileManager.downloadedIDs()
    }

    func classify(_ text: String, using _: String) async throws -> [String: Double] {
        engine.classify(text: text)
    }

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

    static func loadCatalog() throws -> [ModelBundle] {
        do {
            return try loadCatalogFromBundle()
        } catch {
            AppLogger.persistence.error("Falling back to built-in AI catalog: \(error.localizedDescription, privacy: .public)")
            return defaultCatalog
        }
    }

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

extension LiveAIService: OnDeviceAIService {}

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
