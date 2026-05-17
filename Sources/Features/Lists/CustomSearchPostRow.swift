import SwiftUI

struct CustomSearchPostRow: View {
    let entry: RichFeedEntry
    let entries: [RichFeedEntry]
    let loadMore: () async -> Void
    @Binding var imagePreview: ImagePreviewCollection?
    @Binding var videoPreviewURL: URL?
    @Binding var showLikesForURI: String?
    @Binding var showProfileFor: BlueskyActor?
    let availableTargetLists: [BlueskyList]

    var body: some View {
        PostRowView(
            entry: entry,
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
            onShowLikes: { showLikesForURI = entry.post.uri },
            onOpenProfile: { _ in
                let author = entry.post.safeAuthor
                showProfileFor = BlueskyActor(
                    did: author.did ?? "",
                    handle: author.handle ?? "",
                    displayName: author.displayName,
                    avatarURL: author.avatar.flatMap(URL.init)
                )
            },
            onBlockAllLikers: {},
            availableLikerTargetLists: availableTargetLists,
            onAddAllLikersToList: { _ in }
        )
        .buttonStyle(.plain)
        .onAppear {
            if entry.post.uri == entries.last?.post.uri {
                Task { await loadMore() }
            }
        }
    }
}
