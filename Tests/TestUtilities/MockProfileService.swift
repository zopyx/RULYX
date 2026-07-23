import Foundation
@testable import RULYX

/// Mock implementation of BlueskyProfileInspecting for unit testing.
/// All methods return default values or pre-configured results via handler closures.
/// Uses class semantics so handlers can be overridden after VM construction.
@MainActor
final class MockProfileService: BlueskyProfileInspecting {
    var searchActorsHandler: @Sendable (String, AppAccount, String?) async throws -> [BlueskyActor] = { _, _, _ in [] }
    var searchActorsPageHandler: @Sendable (String, String?, AppAccount, String?) async throws -> PagedActorSearch = { _, _, _, _ in PagedActorSearch(actors: [], cursor: nil) }
    var fetchProfileHandler: @Sendable (String, AppAccount, String?) async throws -> BlueskyProfile = { did, _, _ in
        BlueskyProfile(
            id: did,
            did: did,
            handle: "test.bsky.social",
            displayName: nil,
            description: nil,
            websiteURL: nil,
            avatarURL: nil,
            bannerURL: nil,
            followersCount: 0,
            followsCount: 0,
            postsCount: 0,
            listsCount: nil,
            starterPacksCount: nil,
            createdAt: nil,
            labels: [],
            viewerState: nil
        )
    }

    var inspectProfileHandler: @Sendable (String, AppAccount, String?) async throws -> ProfileInspection = { query, _, _ in
        ProfileInspection(
            profile: BlueskyProfile(
                id: query,
                did: query,
                handle: query,
                displayName: nil,
                description: nil,
                websiteURL: nil,
                avatarURL: nil,
                bannerURL: nil,
                followersCount: 0,
                followsCount: 0,
                postsCount: 0,
                listsCount: nil,
                starterPacksCount: nil,
                createdAt: nil,
                labels: [],
                viewerState: nil
            ),
            listMemberships: [],
            starterPackMemberships: []
        )
    }

    var blockActorHandler: @Sendable (String, AppAccount, String?) async throws -> Void = { _, _, _ in }
    var unblockActorHandler: @Sendable (String, AppAccount, String?) async throws -> Void = { _, _, _ in }
    var softBlockActorHandler: @Sendable (String, AppAccount, String?) async throws -> Void = { _, _, _ in }
    var followActorHandler: @Sendable (String, AppAccount, String?) async throws -> Void = { _, _, _ in }
    var unfollowActorHandler: @Sendable (String, AppAccount, String?) async throws -> Void = { _, _, _ in }
    var muteActorHandler: @Sendable (String, AppAccount, String?) async throws -> Void = { _, _, _ in }
    var unmuteActorHandler: @Sendable (String, AppAccount, String?) async throws -> Void = { _, _, _ in }
    var fetchFollowersHandler: @Sendable (String, AppAccount, String?) async throws -> [BlueskyActor] = { _, _, _ in [] }
    var fetchFollowersPageHandler: @Sendable (String, String?, AppAccount, String?) async throws -> PagedActorSearch = { _, _, _, _ in PagedActorSearch(actors: [], cursor: nil) }
    var fetchFollowingHandler: @Sendable (String, AppAccount, String?) async throws -> [BlueskyActor] = { _, _, _ in [] }
    var fetchFollowingPageHandler: @Sendable (String, String?, AppAccount, String?) async throws -> PagedActorSearch = { _, _, _, _ in PagedActorSearch(actors: [], cursor: nil) }
    var reportAccountReasonHandler: @Sendable (String, String?, AppAccount, String?) async throws -> Void = { _, _, _, _ in }
    var reportAccountSimpleHandler: @Sendable (String, String?, AppAccount, String?) async throws -> Void = { _, _, _, _ in }
    var reportAccountTypedHandler: @Sendable (String, ModerationReportReasonType?, String?, AppAccount, String?) async throws -> Void = { _, _, _, _, _ in }
    var putProfileRecordHandler: @Sendable (ProfileRecord, AppAccount, String?) async throws -> Void = { _, _, _ in }
    var fetchExistingBlockedDIDsHandler: @Sendable (AppAccount, String?) async throws -> Set<String> = { _, _ in [] }
    var fetchExistingBlockRecordURIsHandler: @Sendable (AppAccount, String?) async throws -> [String: String] = { _, _ in [:] }

    func searchActors(query: String, account: AppAccount, appPassword: String?) async throws -> [BlueskyActor] {
        try await searchActorsHandler(query, account, appPassword)
    }

    func searchActorsPage(query: String, cursor: String?, account: AppAccount, appPassword: String?) async throws -> PagedActorSearch {
        try await searchActorsPageHandler(query, cursor, account, appPassword)
    }

    func fetchProfile(did actorDID: String, account: AppAccount, appPassword: String?) async throws -> BlueskyProfile {
        try await fetchProfileHandler(actorDID, account, appPassword)
    }

    func inspectProfile(query: String, account: AppAccount, appPassword: String?) async throws -> ProfileInspection {
        try await inspectProfileHandler(query, account, appPassword)
    }

    func blockActor(did actorDID: String, account: AppAccount, appPassword: String?) async throws {
        try await blockActorHandler(actorDID, account, appPassword)
    }

    func unblockActor(recordURI: String, account: AppAccount, appPassword: String?) async throws {
        try await unblockActorHandler(recordURI, account, appPassword)
    }

    func softBlockActor(did actorDID: String, account: AppAccount, appPassword: String?) async throws {
        try await softBlockActorHandler(actorDID, account, appPassword)
    }

    func followActor(did actorDID: String, account: AppAccount, appPassword: String?) async throws {
        try await followActorHandler(actorDID, account, appPassword)
    }

    func unfollowActor(recordURI: String, account: AppAccount, appPassword: String?) async throws {
        try await unfollowActorHandler(recordURI, account, appPassword)
    }

    func muteActor(did actorDID: String, account: AppAccount, appPassword: String?) async throws {
        try await muteActorHandler(actorDID, account, appPassword)
    }

    func unmuteActor(did actorDID: String, account: AppAccount, appPassword: String?) async throws {
        try await unmuteActorHandler(actorDID, account, appPassword)
    }

    func fetchFollowers(actor actorDID: String, account: AppAccount, appPassword: String?) async throws -> [BlueskyActor] {
        try await fetchFollowersHandler(actorDID, account, appPassword)
    }

    func fetchFollowersPage(actor actorDID: String, cursor: String?, account: AppAccount, appPassword: String?) async throws -> PagedActorSearch {
        try await fetchFollowersPageHandler(actorDID, cursor, account, appPassword)
    }

    func fetchFollowing(actor actorDID: String, account: AppAccount, appPassword: String?) async throws -> [BlueskyActor] {
        try await fetchFollowingHandler(actorDID, account, appPassword)
    }

    func fetchFollowingPage(actor actorDID: String, cursor: String?, account: AppAccount, appPassword: String?) async throws -> PagedActorSearch {
        try await fetchFollowingPageHandler(actorDID, cursor, account, appPassword)
    }

    func reportAccount(did targetDID: String, reasonType _: String, reason: String?, account: AppAccount, appPassword: String?) async throws {
        try await reportAccountReasonHandler(targetDID, reason, account, appPassword)
    }

    func reportAccount(did targetDID: String, reason: String?, account: AppAccount, appPassword: String?) async throws {
        try await reportAccountSimpleHandler(targetDID, reason, account, appPassword)
    }

    func reportAccount(did targetDID: String, selectedReason: ModerationReportReasonType?, reason: String?, account: AppAccount, appPassword: String?) async throws {
        try await reportAccountTypedHandler(targetDID, selectedReason, reason, account, appPassword)
    }

    func putProfileRecord(_ record: ProfileRecord, account: AppAccount, appPassword: String?) async throws {
        try await putProfileRecordHandler(record, account, appPassword)
    }

    func fetchExistingBlockedDIDs(account: AppAccount, appPassword: String?) async throws -> Set<String> {
        try await fetchExistingBlockedDIDsHandler(account, appPassword)
    }

    func fetchExistingBlockRecordURIs(account: AppAccount, appPassword: String?) async throws -> [String: String] {
        try await fetchExistingBlockRecordURIsHandler(account, appPassword)
    }
}
