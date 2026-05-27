import SwiftUI

// MARK: - SearchSheetsModifier

/// View modifier that presents sheets for post thread, image carousel,
/// video player, likes list, and profile navigation from search results.
struct SearchSheetsModifier: ViewModifier {
    @Binding var selectedPostURI: String?
    @Binding var imagePreview: ImagePreviewCollection?
    @Binding var videoPreviewURL: URL?
    @Binding var showLikesForURI: String?
    @Binding var showProfileFor: BlueskyActor?
    var accountStore: AccountStore
    var blueskyClient: LiveBlueskyClient

    func body(content: Content) -> some View {
        content
            .sheet(item: $selectedPostURI) { uri in
                NavigationStack {
                    ThreadView(postURI: uri)
                        .environmentObject(accountStore)
                        .environmentObject(blueskyClient)
                        .toolbar {
                            ToolbarItem(placement: .topBarTrailing) {
                                ToolbarCloseButton()
                            }
                        }
                }
            }
            .fullScreenCover(item: $imagePreview) { preview in
                ImageCarouselView(urls: preview.urls, initialIndex: preview.initialIndex) {
                    imagePreview = nil
                }
            }
            .fullScreenCover(item: $videoPreviewURL) { url in
                VideoPlayerView(url: url) {
                    videoPreviewURL = nil
                }
            }
            .sheet(item: $showLikesForURI) { uri in
                LikesListView(uri: uri)
                    .environmentObject(accountStore)
                    .environmentObject(blueskyClient)
            }
            .navigationDestination(item: $showProfileFor) { actor in
                BlueskyProfileView(
                    member: BlueskyListMember(recordURI: "search:\(actor.did)", actor: actor),
                    list: nil
                )
                .environmentObject(accountStore)
                .environmentObject(blueskyClient)
            }
    }
}
