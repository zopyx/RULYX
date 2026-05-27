import SwiftUI

// MARK: - PostDisplayStyle

/// Controls how a post row is rendered.
enum PostDisplayStyle: Equatable {
    /// Complete post with all metadata, embeds, and action bar.
    case full
    /// Condensed layout for timeline feeds (smaller avatar, truncated text).
    case compact
    /// Bare-bones layout for use in list-of-posts contexts (e.g. search results).
    case minimal
    /// Card-styled post for featured or pinned contexts.
    case card
    /// Compact style with a vertical reply connector line, used in thread views.
    case threadReply
}
