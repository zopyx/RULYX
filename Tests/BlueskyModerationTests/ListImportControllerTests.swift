@testable import BlueskyModeration
import XCTest

@MainActor
final class ListImportControllerTests: XCTestCase {
    private var controller: ListImportController!

    override func setUp() async throws {
        try await super.setUp()
        controller = ListImportController()
    }

    func testPreparePreviewClassifiesReadyItems() async throws {
        // swiftlint:disable line_length
        let client = MockImportClient(profiles: [
            "alice.bsky.social": BlueskyProfile(id: "did:plc:alice", did: "did:plc:alice", handle: "alice.bsky.social", displayName: nil, description: nil, websiteURL: nil, avatarURL: nil, bannerURL: nil, followersCount: nil, followsCount: nil, postsCount: nil, listsCount: nil, starterPacksCount: nil, createdAt: nil, labels: [], viewerState: nil),
        ])
        // swiftlint:enable line_length

        let preview = try await controller.preparePreview(
            from: "alice.bsky.social",
            sourceDescription: "Test",
            existingMemberDIDs: [],
            account: AppAccount(handle: "mod.bsky.social"),
            appPassword: "password",
            using: client
        )

        XCTAssertEqual(preview.readyItems.count, 1)
        XCTAssertEqual(preview.readyItems.first?.actor?.handle, "alice.bsky.social")
    }

    func testPreparePreviewClassifiesAlreadyPresent() async throws {
        // swiftlint:disable line_length
        let client = MockImportClient(profiles: [
            "alice.bsky.social": BlueskyProfile(id: "did:plc:alice", did: "did:plc:alice", handle: "alice.bsky.social", displayName: nil, description: nil, websiteURL: nil, avatarURL: nil, bannerURL: nil, followersCount: nil, followsCount: nil, postsCount: nil, listsCount: nil, starterPacksCount: nil, createdAt: nil, labels: [], viewerState: nil),
        ])
        // swiftlint:enable line_length

        let preview = try await controller.preparePreview(
            from: "alice.bsky.social",
            sourceDescription: "Test",
            existingMemberDIDs: ["did:plc:alice"],
            account: AppAccount(handle: "mod.bsky.social"),
            appPassword: "password",
            using: client
        )

        XCTAssertEqual(preview.alreadyPresentItems.count, 1)
        XCTAssertNil(preview.readyItems.first)
    }

    func testPreparePreviewClassifiesDuplicates() async throws {
        // swiftlint:disable line_length
        let client = MockImportClient(profiles: [
            "alice.bsky.social": BlueskyProfile(id: "did:plc:alice", did: "did:plc:alice", handle: "alice.bsky.social", displayName: nil, description: nil, websiteURL: nil, avatarURL: nil, bannerURL: nil, followersCount: nil, followsCount: nil, postsCount: nil, listsCount: nil, starterPacksCount: nil, createdAt: nil, labels: [], viewerState: nil),
        ])
        // swiftlint:enable line_length

        let preview = try await controller.preparePreview(
            from: "alice.bsky.social\nalice.bsky.social",
            sourceDescription: "Test",
            existingMemberDIDs: [],
            account: AppAccount(handle: "mod.bsky.social"),
            appPassword: "password",
            using: client
        )

        XCTAssertEqual(preview.duplicateItems.count, 1)
        XCTAssertEqual(preview.readyItems.count, 1)
    }

    func testPreparePreviewClassifiesUnresolved() async throws {
        let client = MockImportClient(profiles: [:], shouldFail: true)

        let preview = try await controller.preparePreview(
            from: "unknown-handle",
            sourceDescription: "Test",
            existingMemberDIDs: [],
            account: AppAccount(handle: "mod.bsky.social"),
            appPassword: "password",
            using: client
        )

        XCTAssertEqual(preview.unresolvedItems.count, 1)
        XCTAssertTrue(preview.readyItems.isEmpty)
    }

    func testEmptyInputThrowsValidationError() async {
        let client = MockImportClient(profiles: [:])

        do {
            _ = try await controller.preparePreview(
                from: "   ",
                sourceDescription: "Test",
                existingMemberDIDs: [],
                account: AppAccount(handle: "mod.bsky.social"),
                appPassword: "password",
                using: client
            )
            XCTFail("Expected error")
        } catch let error as AppError {
            XCTAssertEqual(error.category, .validation)
        } catch {
            XCTFail("Expected AppError, got \(error)")
        }
    }
}

@MainActor
private final class MockImportClient: LiveBlueskyClient {
    var profiles: [String: BlueskyProfile]
    var shouldFail: Bool

    init(profiles: [String: BlueskyProfile], shouldFail: Bool = false) {
        self.profiles = profiles
        self.shouldFail = shouldFail
        super.init()
    }

    override func fetchProfile(
        did actorDID: String,
        account _: AppAccount,
        appPassword _: String?
    ) async throws -> BlueskyProfile {
        if shouldFail {
            throw BlueskyAPIError.server("Not found")
        }
        guard let profile = profiles[actorDID] else {
            throw BlueskyAPIError.server("Not found")
        }
        return profile
    }
}
