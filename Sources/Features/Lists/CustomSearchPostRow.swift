import SwiftUI

struct CustomSearchPostRow: View {
    let entry: RichFeedEntry
    let entries: [RichFeedEntry]
    let hasMore: Bool
    let isLoadingMore: Bool
    let loadMore: () async -> Void
    @Binding var imagePreview: ImagePreviewCollection?
    @Binding var videoPreviewURL: URL?
    @Binding var showLikesForURI: String?
    @Binding var showProfileFor: BlueskyActor?
    let availableTargetLists: [BlueskyList]
    var onBlockAllLikers: (() -> Void)?
    var onAddAllLikersToList: ((BlueskyList) -> Void)?
    var onClassify: (() -> Void)?
    var onReportPost: (() -> Void)?

    var body: some View {
        PostRowView(
            entry: entry,
            style: .full,
            callbacks: PostRowCallbacks(
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
                onOpenProfile: { _ in
                    let author = entry.post.safeAuthor
                    showProfileFor = BlueskyActor(
                        did: author.did ?? "",
                        handle: author.handle ?? "",
                        displayName: author.displayName,
                        avatarURL: author.avatar.flatMap(URL.init)
                    )
                },
                onShowLikes: { showLikesForURI = entry.post.uri },
                onReportPost: onReportPost,
                onBlockAllLikers: onBlockAllLikers,
                onAddAllLikersToList: onAddAllLikersToList,
                onClassify: onClassify,
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
