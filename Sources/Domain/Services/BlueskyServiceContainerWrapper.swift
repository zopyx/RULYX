import Foundation

/// Observable wrapper around BlueskyServiceContainer for @EnvironmentObject injection.
/// Provides forwarding properties for each service protocol, eliminating the
/// force-cast `blueskyClient` passthrough.
///
/// Usage: `container.profile.fetchProfile(...)` instead of `container.profile.fetchProfile(...)`
@MainActor
final class BlueskyServiceContainerWrapper: ObservableObject {
    let container: BlueskyServiceContainer
    /// Direct reference to the production client — avoids the `as!` force-cast
    /// in the deprecated accessor below. Remove when all callers are migrated
    /// to protocol properties.
    private let liveClient: LiveBlueskyClient

    // MARK: - Protocol Forwarding Properties

    var auth: BlueskyAuthServicing { container.auth }
    var profile: BlueskyProfileInspecting { container.profile }
    var list: BlueskyListServicing { container.list }
    var feed: BlueskyFeedServicing { container.feed }
    var post: BlueskyPostServicing { container.post }
    var social: BlueskySocialServicing { container.social }
    var moderation: BlueskyModerationServicing { container.moderation }
    var clearsky: BlueskyClearSkyServicing { container.clearsky }
    var notification: BlueskyNotificationServicing { container.notification }
    var identity: BlueskyIdentityServicing { container.identity }
    var media: BlueskyMediaServicing { container.media }

    /// Legacy accessor — returns the same LiveBlueskyClient instance.
    /// Prefer using the individual protocol properties above.
    @available(*, deprecated, message: "Use individual protocol properties (container.profile, container.list, etc.)")
    var blueskyClient: LiveBlueskyClient { liveClient }

    // MARK: - Init

    init(liveClient: LiveBlueskyClient, accountStore: AccountStoreProtocol) {
        self.liveClient = liveClient
        container = BlueskyServiceContainer(liveClient: liveClient, accountStore: accountStore)
    }
}
