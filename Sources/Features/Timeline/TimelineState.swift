import Foundation

// MARK: - TimelineState

/// Represents the loading/empty/error state of the timeline feed.
enum TimelineState: Equatable {
    case initialLoading
    case loaded
    case refreshing
    case loadingMore
    case loadMoreFailed(String)
    case empty
    case failed(String)
    case exhausted

    /// Extracts the error message from failed or loadMoreFailed states.
    var errorMessage: String? {
        switch self {
        case let .loadMoreFailed(msg), let .failed(msg): msg
        default: nil
        }
    }

    /// Whether the timeline is currently fetching data.
    var isLoading: Bool {
        switch self {
        case .initialLoading, .refreshing, .loadingMore: true
        default: false
        }
    }

    /// Whether more pages can be loaded.
    var hasMore: Bool {
        switch self {
        case .exhausted, .failed: false
        default: true
        }
    }

    /// Whether the timeline has no content.
    var isEmpty: Bool {
        self == .empty
    }
}
