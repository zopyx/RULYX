import Foundation

/// Observable wrapper around BlueskyServiceContainer for @EnvironmentObject injection.
/// Stores the LiveBlueskyClient directly (no force-cast) alongside the protocol container.
@MainActor
final class BlueskyServiceContainerWrapper: ObservableObject {
    let container: BlueskyServiceContainer

    /// The underlying LiveBlueskyClient, stored directly for type-safe access.
    /// Avoids force-casting from the container's protocol-typed properties.
    let blueskyClient: LiveBlueskyClient

    init(liveClient: LiveBlueskyClient, accountStore: AccountStoreProtocol) {
        self.blueskyClient = liveClient
        self.container = BlueskyServiceContainer(liveClient: liveClient, accountStore: accountStore)
    }
}
