import Foundation

/// Observable wrapper around BlueskyServiceContainer for @EnvironmentObject injection.
/// Provides forwarding properties for each service protocol, eliminating the
/// force-cast `blueskyClient` passthrough.
///
/// Usage: `container.profile.fetchProfile(...)` for protocol-based calls.
/// Use `container.liveClient` only for legacy APIs that still require the
/// concrete `LiveBlueskyClient` type.
@MainActor
final class BlueskyServiceContainerWrapper: ObservableObject {
    let container: BlueskyServiceContainer

    /// The concrete live client, for legacy APIs that still require
    /// `LiveBlueskyClient` (e.g. view models not yet re-typed to protocols).
    /// Prefer the individual protocol properties below for new code.
    let liveClient: LiveBlueskyClient

    // MARK: - Protocol Forwarding Properties

    var auth: BlueskyAuthServicing {
        container.auth
    }

    var authenticating: BlueskyAuthenticating {
        container.authenticating
    }

    var profile: BlueskyProfileInspecting {
        container.profile
    }

    var list: BlueskyListServicing {
        container.list
    }

    var feed: BlueskyFeedServicing {
        container.feed
    }

    var post: BlueskyPostServicing {
        container.post
    }

    var social: BlueskySocialServicing {
        container.social
    }

    var moderation: BlueskyModerationServicing {
        container.moderation
    }

    var clearsky: BlueskyClearSkyServicing {
        container.clearsky
    }

    var notification: BlueskyNotificationServicing {
        container.notification
    }

    var identity: BlueskyIdentityServicing {
        container.identity
    }

    var media: BlueskyMediaServicing {
        container.media
    }

    // MARK: - Init

    init(liveClient: LiveBlueskyClient, accountStore: AccountStoreProtocol) {
        self.liveClient = liveClient
        container = BlueskyServiceContainer(liveClient: liveClient, accountStore: accountStore)
    }
}
