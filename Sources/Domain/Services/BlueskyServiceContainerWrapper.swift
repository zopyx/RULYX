import Foundation

/// Observable wrapper around BlueskyServiceContainer for @EnvironmentObject injection.
/// Provides forwarding properties for each service protocol, eliminating the
/// force-cast `blueskyClient` passthrough.
///
/// Usage: `container.profile.fetchProfile(...)` instead of `container.profile.fetchProfile(...)`
@MainActor
final class BlueskyServiceContainerWrapper: ObservableObject {
    let container: BlueskyServiceContainer

    // MARK: - Protocol Forwarding Properties

    var auth: BlueskyAuthServicing {
        container.auth
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

    /// Legacy accessor for parameter passing to functions that still accept `LiveBlueskyClient`.
    /// Prefer using the individual protocol properties above for direct method calls.
    /// 
    /// Migration guide (83 environment + 120 parameter sites across ~40 files):
    /// 1. Replace `.environmentObject(container.blueskyClient)` → `.environmentObject(container)`
    /// 2. In child views: `@EnvironmentObject var client: LiveBlueskyClient` → `@EnvironmentObject var container: BlueskyServiceContainerWrapper`
    /// 3. Replace `client.method()` with the appropriate protocol: `container.social.method()` etc.
    /// 4. For `using: container.blueskyClient` parameters: change VM method signature from `LiveBlueskyClient` to the specific protocol it uses.
    @available(*, deprecated, message: "Use individual protocol properties (container.profile, container.list, etc.)")
    var blueskyClient: LiveBlueskyClient {
        container.auth as! LiveBlueskyClient
    }

    // MARK: - Init

    init(liveClient: LiveBlueskyClient, accountStore: AccountStoreProtocol) {
        container = BlueskyServiceContainer(liveClient: liveClient, accountStore: accountStore)
    }
}
