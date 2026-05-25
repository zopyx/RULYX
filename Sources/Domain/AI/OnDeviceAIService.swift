import Foundation

// MARK: - Model Role

enum ModelRole: String, Codable, CaseIterable {
    case textClassifier
    case textGenerator
}

// MARK: - Model Bundle

struct ModelBundle: Identifiable, Codable, Hashable {
    let id: String
    let name: String
    let role: ModelRole
    let downloadURL: URL
    let fileSize: Int64
    let description: String
    let requires: String

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: ModelBundle, rhs: ModelBundle) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Download State

enum ModelDownloadState: Equatable {
    case notDownloaded
    case downloading(Double)
    case ready
    case failed(String)
}

// MARK: - Error

struct AIError: LocalizedError {
    let message: String
    var errorDescription: String? {
        message
    }

    init(_ message: String) {
        self.message = message
    }

    static let modelNotDownloadedMessage = "ai.error.not_downloaded"
    static let modelNotLoadedMessage = "ai.error.not_loaded"
    static let unsupportedRoleMessage = "ai.error.unsupported_role"
    static let downloadFailedMessage = "ai.error.download_failed"
    static let runtimeNotAvailableMessage = "ai.error.runtime_not_available"
}

// MARK: - Service Protocol

@MainActor
protocol OnDeviceAIService: AnyObject {
    var catalog: [ModelBundle] { get async }
    var downloadStates: [String: ModelDownloadState] { get }

    func refreshCatalog() async throws
    func download(_ model: ModelBundle) async throws
    func delete(_ modelID: String) async throws
    func state(for modelID: String) -> ModelDownloadState
    func downloadedModelIDs() -> [String]

    func classify(_ text: String, using modelID: String) async throws -> [String: Double]
    func complete(prompt: String, using modelID: String) -> AsyncThrowingStream<String, Error>
}
