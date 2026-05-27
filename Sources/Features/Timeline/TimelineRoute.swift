import Foundation

// MARK: - TimelineRoute

/// Navigation destinations available from the timeline.
enum TimelineRoute: Hashable {
    case thread(postURI: String)
}
