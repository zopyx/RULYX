import Foundation

enum TimelineState: Equatable {
    case initialLoading
    case loaded
    case refreshing
    case loadingMore
    case loadMoreFailed(String)
    case empty
    case failed(String)
    case exhausted

    var errorMessage: String? {
        switch self {
        case let .loadMoreFailed(msg), let .failed(msg): msg
        default: nil
        }
    }

    var isLoading: Bool {
        switch self {
        case .initialLoading, .refreshing, .loadingMore: true
        default: false
        }
    }

    var hasMore: Bool {
        switch self {
        case .exhausted, .failed: false
        default: true
        }
    }

    var isEmpty: Bool {
        self == .empty
    }
}
