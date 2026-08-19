import SwiftUI

// MARK: - CustomSearchPostRow

/// A post row for custom search results, wrapping `PostRowView` with
/// image preview, video playback, profile navigation, and liker actions.
struct CustomSearchPostRow: View {
    let entry: RichFeedEntry
    let entries: [RichFeedEntry]
    let hasMore: Bool
    let isLoadingMore: Bool
    let loadMore: () async -> Void
    @Binding var imagePreview: ImagePreviewCollection?
    @Binding var videoPreviewURL: URL?
    @Binding var showLikesForURI: String?
    let onOpenProfile: ((String) -> Void)?
    let availableTargetLists: [BlueskyList]
    var onBlockAllLikers: (() -> Void)?
    var onAddAllLikersToList: ((BlueskyList) -> Void)?
    var onClassify: (() -> Void)?
    var onReportPost: (() -> Void)?
    var onBlockAuthor: (() -> Void)?
    var onAddAuthorToList: ((BlueskyList) -> Void)?
    var onTapThread: (() -> Void)?

    // MARK: - Body

    var body: some View {
        PostRowView(
            entry: entry,
            style: .full,
            callbacks: PostRowCallbacks(
                onTapThread: onTapThread,
                onTapImage: { index in
                    let urls = (entry.post.embed?.images ?? []).compactMap { $0.fullsize.flatMap(URL.init) }
                    guard index < urls.count else { return }
                    imagePreview = ImagePreviewCollection(urls: urls, initialIndex: index)
                },
                onPlayVideo: {
                    if let playlist = entry.post.embed?.video?.playlist, let url = URL(string: playlist) {
                        videoPreviewURL = url
                    }
                },
                onOpenProfile: { handle in onOpenProfile?(handle) },
                onShowLikes: { showLikesForURI = entry.post.uri },
                onReportPost: onReportPost,
                onBlockAllLikers: onBlockAllLikers,
                onAddAllLikersToList: onAddAllLikersToList,
                onClassify: onClassify,
                onBlockAuthor: onBlockAuthor,
                onAddAuthorToList: onAddAuthorToList,
                availableLikerTargetLists: availableTargetLists
            )
        )
        .buttonStyle(.plain)
        .postInfiniteScroll(
            entry: entry,
            entries: entries,
            hasMore: hasMore,
            isLoadingMore: isLoadingMore,
            loadMore: loadMore
        )
    }
}
