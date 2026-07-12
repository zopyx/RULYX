import Foundation

/// Observable wrapper around BlueskyServiceContainer for @EnvironmentObject injection.
@MainActor
final class BlueskyServiceContainerWrapper: ObservableObject {
    let container: BlueskyServiceContainer

    /// Convenience accessor that returns the underlying LiveBlueskyClient.
    /// Safe because all protocol properties are backed by the same client instance.
    var blueskyClient: LiveBlueskyClient {
        container.auth as! LiveBlueskyClient
    }

    init(liveClient: LiveBlueskyClient, accountStore: AccountStoreProtocol) {
        self.container = BlueskyServiceContainer(liveClient: liveClient, accountStore: accountStore)
    }
}
