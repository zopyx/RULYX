import SwiftUI

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
                ThreadView(postURI: uri)
                    .environmentObject(accountStore)
                    .environmentObject(blueskyClient)
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
