import Foundation

// MARK: - ModelRole

/// Describes the inference capability of a model bundle.
enum ModelRole: String, Codable, CaseIterable {
    /// Model used for text classification (toxicity, spam, etc.).
    case textClassifier
    /// Model used for text generation / completion.
    case textGenerator
}

// MARK: - ModelBundle

/// Describes an AI model available for download and on-device inference.
struct ModelBundle: Identifiable, Codable, Hashable {
    /// Unique identifier for the model (e.g. ``phi-3-mini-q4``).
    let id: String
    /// Human-readable display name.
    let name: String
    /// The inference role this model fulfills.
    let role: ModelRole
    /// Remote URL from which the model can be downloaded.
    let downloadURL: URL
    /// File size of the model binary in bytes.
    let fileSize: Int64
    /// Description of the model's capabilities.
    let description: String
    /// Minimum iOS version requirement string (e.g. ``17.0``).
    let requires: String

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: ModelBundle, rhs: ModelBundle) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - ModelDownloadState

/// Represents the download progress of an on-device model.
enum ModelDownloadState: Equatable {
    /// No download has been initiated.
    case notDownloaded
    /// Download is in progress with a progress value of 0.0–1.0.
    case downloading(Double)
    /// The model is fully downloaded and ready for inference.
    case ready
    /// Download failed with an associated error message.
    case failed(String)
}

// MARK: - AIError

/// Errors related to on-device AI operations.
struct AIError: LocalizedError {
    /// The underlying error message.
    let message: String
    var errorDescription: String? {
        message
    }

    /// Creates an AI error with the given message.
    init(_ message: String) {
        self.message = message
    }

    /// Localization key for "model not downloaded" error message.
    static let modelNotDownloadedMessage = "ai.error.not_downloaded"
    /// Localization key for "model not loaded" error message.
    static let modelNotLoadedMessage = "ai.error.not_loaded"
    /// Localization key for "unsupported role" error message.
    static let unsupportedRoleMessage = "ai.error.unsupported_role"
    /// Localization key for "download failed" error message.
    static let downloadFailedMessage = "ai.error.download_failed"
    /// Localization key for "runtime not available" error message.
    static let runtimeNotAvailableMessage = "ai.error.runtime_not_available"
}

// MARK: - OnDeviceAIService

/// Protocol abstracting the on-device AI service, providing catalog management,
/// model download control, and inference capabilities.
@MainActor
protocol OnDeviceAIService: AnyObject {
    /// The list of available model bundles.
    var catalog: [ModelBundle] { get async }
    /// Dictionary of model download states keyed by model ID.
    var downloadStates: [String: ModelDownloadState] { get }

    /// Reloads the model catalog from the bundled manifest or fallback.
    func refreshCatalog() async throws
    /// Downloads the specified model from its remote URL.
    func download(_ model: ModelBundle) async throws
    /// Deletes a downloaded model from disk.
    func delete(_ modelID: String) async throws
    /// Returns the current download state for a model.
    func state(for modelID: String) -> ModelDownloadState
    /// Returns the IDs of all fully downloaded models.
    func downloadedModelIDs() -> [String]

    /// Classifies text using the specified model.
    func classify(_ text: String, using modelID: String) async throws -> [String: Double]
    /// Generates text using the specified model, yielding tokens via an async stream.
    func complete(prompt: String, using modelID: String) -> AsyncThrowingStream<String, Error>
}
