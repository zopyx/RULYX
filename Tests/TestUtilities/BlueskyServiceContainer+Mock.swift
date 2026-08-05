@testable import RULYX

extension BlueskyServiceContainer {
    static func mock(
        profile: BlueskyProfileInspecting = MockProfileService(),
        clearsky: BlueskyClearSkyServicing = MockClearSkyService(),
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
            clearsky: clearsky,
            notification: MockNotificationService(),
            identity: MockIdentityService(),
            media: MockMediaService(),
            accountStore: accountStore
        )
    }
}
