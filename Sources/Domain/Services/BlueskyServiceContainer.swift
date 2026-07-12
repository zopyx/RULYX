import Foundation

/// Centralized dependency container for Bluesky service protocols.
/// Replaces scattered @EnvironmentObject injection with a single container.
@MainActor
struct BlueskyServiceContainer {
    let auth: BlueskyAuthServicing
    let profile: BlueskyProfileInspecting
    let list: BlueskyListServicing
    let feed: BlueskyFeedServicing
    let post: BlueskyPostServicing
    let social: BlueskySocialServicing
    let moderation: BlueskyModerationServicing
    let clearsky: BlueskyClearSkyServicing
    let notification: BlueskyNotificationServicing
    let identity: BlueskyIdentityServicing
    let media: BlueskyMediaServicing
    let accountStore: AccountStoreProtocol

    init(liveClient: LiveBlueskyClient, accountStore: AccountStoreProtocol) {
        self.auth = liveClient
        self.profile = liveClient
        self.list = liveClient
        self.feed = liveClient
        self.post = liveClient
        self.social = liveClient
        self.moderation = liveClient
        self.clearsky = liveClient
        self.notification = liveClient
        self.identity = liveClient
        self.media = liveClient
        self.accountStore = accountStore
    }

    init(
        auth: BlueskyAuthServicing,
        profile: BlueskyProfileInspecting,
        list: BlueskyListServicing,
        feed: BlueskyFeedServicing,
        post: BlueskyPostServicing,
        social: BlueskySocialServicing,
        moderation: BlueskyModerationServicing,
        clearsky: BlueskyClearSkyServicing,
        notification: BlueskyNotificationServicing,
        identity: BlueskyIdentityServicing,
        media: BlueskyMediaServicing,
        accountStore: AccountStoreProtocol
    ) {
        self.auth = auth
        self.profile = profile
        self.list = list
        self.feed = feed
        self.post = post
        self.social = social
        self.moderation = moderation
        self.clearsky = clearsky
        self.notification = notification
        self.identity = identity
        self.media = media
        self.accountStore = accountStore
    }
}
