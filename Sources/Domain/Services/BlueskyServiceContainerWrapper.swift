import Foundation

/// Observable wrapper around BlueskyServiceContainer for @EnvironmentObject injection.
@MainActor
final class BlueskyServiceContainerWrapper: ObservableObject {
    let container: BlueskyServiceContainer

    init(liveClient: LiveBlueskyClient, accountStore: AccountStoreProtocol) {
        self.container = BlueskyServiceContainer(liveClient: liveClient, accountStore: accountStore)
    }
}
