import Foundation

/// Timeline, feed, and author feed operations.
@MainActor
protocol BlueskyFeedServicing: Sendable {
    /// Fetch the home timeline.
    func fetchTimeline(
        cursor: String?,
        limit: Int,
        account: AppAccount,
        appPassword: String?
    ) async throws -> RichFeedResponse

    /// Fetch a custom feed by URI.
    func fetchFeed(
        feedURI: String,
        cursor: String?,
        limit: Int,
        account: AppAccount,
        appPassword: String?
    ) async throws -> RichFeedResponse

    /// Fetch the feed for a specific list.
    func fetchListFeed(
        listURI: String,
        cursor: String?,
        limit: Int,
        account: AppAccount,
        appPassword: String?
    ) async throws -> RichFeedResponse

    /// Fetch the author feed for a given DID.
    func fetchAuthorFeed(
        did: String,
        cursor: String?,
        account: AppAccount,
        appPassword: String?
    ) async throws -> GetAuthorFeedResponse

    /// Fetch a rich feed for a given DID.
    func fetchRichFeed(
        did: String,
        cursor: String?,
        filter: String?,
        account: AppAccount,
        appPassword: String?
    ) async throws -> RichFeedResponse
}
