import Foundation

// MARK: - SearchToken

/// A simple token for guarding against stale search results.
/// Create a new token before starting a search, and check `matches`
/// before applying the results (discard if the token has been superseded).
@MainActor
final class SearchToken {
    private nonisolated let id: UUID

    // MARK: - Init

    init() {
        id = UUID()
    }

    /// Returns true if the receiver matches the provided token.
    func matches(_ other: SearchToken) -> Bool {
        id == other.id
    }
}
