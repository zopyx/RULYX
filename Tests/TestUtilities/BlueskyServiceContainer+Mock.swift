@testable import RULYX

extension BlueskyServiceContainer {
    static func mock(
        profile: BlueskyProfileInspecting = MockProfileService(),
        blocklist: BlueskyBlocklistServicing = MockBlocklistService(),
        list: BlueskyListServicing = MockListService(),
        accountStore: AccountStoreProtocol = MockAccountStore()
    ) -> BlueskyServiceContainer {
        BlueskyServiceContainer(
            auth: MockAuthService(),
            authenticating: MockAuthenticatingService(),
            profile: profile,
            list: list,
            feed: MockFeedService(),
            post: MockPostService(),
            social: MockSocialService(),
            moderation: MockModerationService(),
            blocklist: blocklist,
            notification: MockNotificationService(),
            identity: MockIdentityService(),
            media: MockMediaService(),
            accountStore: accountStore
        )
    }
}
