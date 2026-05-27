import Foundation

/// A preview/mock AI service that overrides `LiveAIService` with deterministic
/// behavior and simulated latency. Used in SwiftUI previews and tests.
@MainActor
final class PreviewAIService: LiveAIService {
    /// Overridden catalog used instead of loading from the bundle.
    private var catalogOverride: [ModelBundle]
    /// Set of model IDs that are considered "downloaded".
    private var downloaded: Set<String> = []

    /// Initializes with the preview catalog.
    override init() {
        catalogOverride = Self.previewCatalog
        super.init()
    }

    private static let previewCatalog: [ModelBundle] = [
        ModelBundle(
            id: "toxicity-classifier-v1",
            name: "Toxicity Classifier",
            role: .textClassifier,
            downloadURL: URL(string: "https://example.com/models/toxicity-v1.mlpackage.zip")!,
            fileSize: 4_194_304,
            description: "Detects toxic, harassing, and abusive language in posts.",
            requires: "17.0"
        ),
        ModelBundle(
            id: "phi-3-mini-q4",
            name: "Phi-3 Mini (Q4)",
            role: .textGenerator,
            downloadURL: URL(string: "https://example.com/models/phi-3-mini-q4.gguf")!,
            fileSize: 2_147_483_648,
            description: "Microsoft Phi-3 mini 3.8B parameter model, 4-bit quantized.",
            requires: "17.0"
        ),
    ]

    /// Rebuilds `downloadStates` based on the `downloaded` set.
    private func updateStates() {
        var states: [String: ModelDownloadState] = [:]
        for model in catalogOverride {
            states[model.id] = downloaded.contains(model.id) ? .ready : .notDownloaded
        }
        downloadStates = states
    }

    override var catalog: [ModelBundle] {
        get async { catalogOverride }
    }

    override func refreshCatalog() async throws {
        do {
            catalogOverride = try Self.loadCatalog()
        } catch {
            catalogOverride = Self.previewCatalog
        }
        updateStates()
    }

    override func download(_ model: ModelBundle) async throws {
        try await Task.sleep(for: .seconds(1))
        downloaded.insert(model.id)
        updateStates()
    }

    override func delete(_ modelID: String) async throws {
        downloaded.remove(modelID)
        updateStates()
    }

    override func state(for modelID: String) -> ModelDownloadState {
        downloaded.contains(modelID) ? .ready : .notDownloaded
    }

    override func downloadedModelIDs() -> [String] {
        Array(downloaded)
    }

    override func classify(_: String, using _: String) async throws -> [String: Double] {
        try await Task.sleep(for: .milliseconds(200))
        return [
            "toxic": 0.05,
            "harassment": 0.02,
            "spam": 0.01,
            "safe": 0.92,
        ]
    }

    override func complete(prompt _: String, using _: String) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
                let words = [
                    "This", "post", "appears", "to", "be", "a", "spam",
                    "account", "based", "on", "its", "pattern", "of",
                    "repetitive", "content", "and", "new", "account", "age.",
                ]
                for (i, word) in words.enumerated() {
                    continuation.yield(word + (i < words.count - 1 ? " " : ""))
                    try await Task.sleep(for: .milliseconds(80))
                }
                continuation.finish()
            }
        }
    }
}
