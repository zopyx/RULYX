import Foundation

/// Post creation, threads, search, and record deletion.
@MainActor
protocol BlueskyPostServicing: Sendable {
    /// Fetch a post thread.
    func fetchPostThread(
        uri: String,
        depth: Int?,
        account: AppAccount,
        appPassword: String?
    ) async throws -> GetPostThreadResponse

    /// Create a new post with optional embeds, reply, quote, and gate rules.
    func createPost(
        text: String,
        images: [PostImageAttachment]?,
        video: PostVideoAttachment?,
        external: PostExternalAttachment?,
        replyTo: (parentURI: String, parentCID: String, rootURI: String, rootCID: String)?,
        quote: (uri: String, cid: String)?,
        threadGate: ThreadGateRule?,
        allowQuoting: Bool,
        account: AppAccount,
        appPassword: String?
    ) async throws -> CreateRecordResponse

    /// Create a thread gate for a post.
    func createThreadGate(
        postURI: String,
        rules: [ThreadGateRule],
        account: AppAccount,
        appPassword: String?
    ) async throws -> CreateRecordResponse

    /// Create a post gate to disable quote-embedding.
    func createPostGate(
        postURI: String,
        account: AppAccount,
        appPassword: String?
    ) async throws -> CreateRecordResponse

    /// Delete a record by URI.
    func deleteRecord(
        recordURI: String,
        account: AppAccount,
        appPassword: String?
    ) async throws -> EmptyResponse

    /// Fetch posts by URIs.
    func fetchPosts(uris: [String]) async throws -> [RichPost]

    /// Search posts with optional filters.
    func searchPosts(
        q: String,
        mentions: String?,
        sort: String?,
        cursor: String?,
        limit: Int,
        account: AppAccount,
        appPassword: String?
    ) async throws -> SearchPostsResponse
}
