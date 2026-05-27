import SwiftUI

// MARK: - PostInfiniteScrollModifier

/// A `ViewModifier` that triggers `loadMore` when the last visible entry appears.
/// Used for paginated timeline feeds.
struct PostInfiniteScrollModifier: ViewModifier {
    /// The current entry being rendered.
    let entry: RichFeedEntry
    /// All currently loaded entries.
    let entries: [RichFeedEntry]
    /// Whether there are more pages to load.
    let hasMore: Bool
    /// Whether a load operation is already in progress.
    let isLoadingMore: Bool
    /// Async closure to fetch the next page.
    let loadMore: () async -> Void

    // MARK: - ViewModifier

    func body(content: Content) -> some View {
        content
            .onAppear {
                guard hasMore, !isLoadingMore else { return }
                // Fire when this entry is the last in the list
                if entry.post.uri == entries.last?.post.uri {
                    Task { await loadMore() }
                }
            }
    }
}

extension View {
    /// Trigger `loadMore` when the given entry is the last visible item and more data exists.
    func postInfiniteScroll(
        entry: RichFeedEntry,
        entries: [RichFeedEntry],
        hasMore: Bool = true,
        isLoadingMore: Bool = false,
        loadMore: @escaping () async -> Void
    ) -> some View {
        modifier(PostInfiniteScrollModifier(
            entry: entry,
            entries: entries,
            hasMore: hasMore,
            isLoadingMore: isLoadingMore,
            loadMore: loadMore
        ))
    }
}
