import SwiftUI

struct PostInfiniteScrollModifier: ViewModifier {
    let entry: RichFeedEntry
    let entries: [RichFeedEntry]
    let hasMore: Bool
    let isLoadingMore: Bool
    let loadMore: () async -> Void

    func body(content: Content) -> some View {
        content
            .onAppear {
                guard hasMore, !isLoadingMore else { return }
                if entry.post.uri == entries.last?.post.uri {
                    Task { await loadMore() }
                }
            }
    }
}

extension View {
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
