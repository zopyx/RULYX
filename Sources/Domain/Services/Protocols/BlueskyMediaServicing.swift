import Foundation

/// Media upload operations.
@MainActor
protocol BlueskyMediaServicing: Sendable {
    /// Upload a blob (image, video, etc.) to the user's PDS.
    func uploadBlob(
        data: Data,
        mimeType: String,
        account: AppAccount,
        appPassword: String?,
        progress: (@Sendable (Double) -> Void)?
    ) async throws -> UploadBlobResponse
}
