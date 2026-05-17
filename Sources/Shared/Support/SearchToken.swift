import Foundation

/// A simple token for guarding against stale search results.
/// Create a new token before starting a search, and check `isCurrent`
/// before applying the results.
@MainActor
final class SearchToken: Sendable {
    private nonisolated let id: UUID

    init() {
        id = UUID()
    }

    /// Returns true if the receiver matches the provided token.
    func matches(_ other: SearchToken) -> Bool {
        id == other.id
    }
}
