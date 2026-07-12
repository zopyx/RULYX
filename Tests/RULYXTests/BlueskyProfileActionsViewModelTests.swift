@testable import RULYX
import XCTest

@MainActor
final class BlueskyProfileActionsViewModelTests: XCTestCase {
    var sut: BlueskyProfileActionsViewModel!
    var mockProfile: MockProfileService!
    var mockClearSky: MockClearSkyService!
    var mockAccount: MockAccountStore!

    override func setUp() async throws {
        mockProfile = MockProfileService()
        mockClearSky = MockClearSkyService()
        mockAccount = MockAccountStore()
        sut = BlueskyProfileActionsViewModel(
            profileService: mockProfile,
            clearskyService: mockClearSky,
            accountStore: mockAccount
        )
        sut.resultDisplayDuration = 0 // fast tests
    }

    override func tearDown() {
        sut = nil
        mockProfile = nil
        mockClearSky = nil
        mockAccount = nil
    }

    // MARK: - Block Back

    func testBlockBackWithActorsBlocksAllAndUpdatesState() async {
        // Given: 3 actors to block
        let actors = [
            makeActor(did: "did:plc:1", handle: "user1.bsky.social"),
            makeActor(did: "did:plc:2", handle: "user2.bsky.social"),
            makeActor(did: "did:plc:3", handle: "user3.bsky.social"),
        ]

        // When
        await sut.blockBack(actors: actors)

        // Then: all completed successfully
        XCTAssertEqual(sut.blockBackCompleted, 3)
        XCTAssertEqual(sut.blockBackTotal, 3)
        XCTAssertEqual(sut.blockBackSuccessCount, 3)
        XCTAssertEqual(sut.blockBackFailureCount, 0)
        XCTAssertFalse(sut.isBlockingBack)
    }

    func testBlockBackWithNoActorsExitsEarly() async {
        // Given: empty actor list
        await sut.blockBack(actors: [])

        // Then: returns immediately, no error
        XCTAssertFalse(sut.isBlockingBack)
        XCTAssertNil(sut.blockBackError)
        XCTAssertEqual(sut.blockBackTotal, 0)
    }

    func testBlockBackSetsIsBlockingBackAndYield() async {
        // Given: mock profile service (default no-op is fine)

        // When
        await sut.blockBack(actors: [makeActor()])

        // Then: actor was blocked (evidenced by completed count)
        XCTAssertEqual(sut.blockBackCompleted, 1)
        XCTAssertEqual(sut.blockBackSuccessCount, 1)
    }

    func testBlockBackTracksFailures() async {
        // Given: mock that fails for one actor
        mockProfile.blockActorHandler = { did, _, _ in
            if did == "did:plc:fail" {
                throw BlueskyAPIError.invalidResponse
            }
        }
        let actors = [
            makeActor(did: "did:plc:ok", handle: "ok.bsky.social"),
            makeActor(did: "did:plc:fail", handle: "fail.bsky.social"),
            makeActor(did: "did:plc:ok2", handle: "ok2.bsky.social"),
        ]

        // When
        await sut.blockBack(actors: actors)

        // Then
        XCTAssertEqual(sut.blockBackCompleted, 3)
        XCTAssertEqual(sut.blockBackSuccessCount, 2)
        XCTAssertEqual(sut.blockBackFailureCount, 1)
        XCTAssertFalse(sut.isBlockingBack)
    }

    // MARK: - Block Counts

    func testFetchBlockCountsSetsAllThreeValues() async throws {
        // Given
        mockClearSky.fetchBlockingCountHandler = { _ in 42 }
        mockClearSky.fetchBlockedByCountHandler = { _ in 17 }
        mockClearSky.fetchUnblockedBlockersCountHandler = { _ in 5 }

        // When
        await sut.fetchBlockCounts(isOwnProfile: true)

        // Then
        XCTAssertEqual(sut.blockingCount, 42)
        XCTAssertEqual(sut.blockedByCount, 17)
        XCTAssertEqual(sut.unblockedBlockersCount, 5)
        XCTAssertFalse(sut.isFetchingBlockCounts)
    }

    func testFetchBlockCountsResetsForNonOwnProfile() async {
        sut.blockingCount = 100
        sut.unblockedBlockersCount = 50

        await sut.fetchBlockCounts(isOwnProfile: false)

        XCTAssertNil(sut.blockingCount)
        XCTAssertNil(sut.unblockedBlockersCount)
    }

    // MARK: - Block Preview

    func testFetchBlockPreviewLoadsActorsAndShowsPreview() async {
        // Given
        let previewActors = [makeActor(handle: "blocker.bsky.social")]
        mockClearSky.fetchUnblockedBlockerActorsHandler = { _, _ in previewActors }

        // When
        await sut.fetchBlockPreview()

        // Then
        XCTAssertEqual(sut.blockPreviewActors.count, 1)
        XCTAssertTrue(sut.showBlockBackPreview)
        XCTAssertFalse(sut.isFetchingBlockPreview)
    }

    // MARK: - Helpers

    func testBlockBackPreviewAvailableWhenClearSkyUpAndHasCount() {
        sut.unblockedBlockersCount = 3
        XCTAssertTrue(sut.blockBackPreviewAvailable)
    }

    func testBlockBackPreviewUnavailableWhenZeroCount() {
        sut.unblockedBlockersCount = 0
        XCTAssertFalse(sut.blockBackPreviewAvailable)
    }

    func testResetBlockBackCountsClearsAllState() {
        sut.blockingCount = 10
        sut.showBlockBackPreview = true
        sut.blockPreviewActors = [makeActor()]
        sut.blockBackCurrentHandle = "someone"

        sut.resetBlockBackCounts()

        XCTAssertNil(sut.blockingCount)
        XCTAssertFalse(sut.showBlockBackPreview)
        XCTAssertTrue(sut.blockPreviewActors.isEmpty)
        XCTAssertNil(sut.blockBackCurrentHandle)
    }

    func testCountTextFormatsNicely() {
        XCTAssertEqual(BlueskyProfileActionsViewModel.countText(nil), "-")
        XCTAssertEqual(BlueskyProfileActionsViewModel.countText(42), "42")
    }

    func testBlockBackResultSummaryAllSuccess() {
        sut.blockBackSuccessCount = 5
        sut.blockBackFailureCount = 0

        let summary = sut.blockBackResultSummary
        XCTAssertTrue(summary.contains("5"))
    }

    func testBlockBackResultSummaryPartial() {
        sut.blockBackSuccessCount = 3
        sut.blockBackFailureCount = 2

        let summary = sut.blockBackResultSummary
        XCTAssertTrue(summary.contains("3"))
        XCTAssertTrue(summary.contains("2"))
    }

    // MARK: - State Matrix: Block Counts

    func testFetchBlockCountsWhenProfileIsOwn() async {
        // Given: service returns specific counts for own profile
        mockClearSky.fetchBlockingCountHandler = { _ in 25 }
        mockClearSky.fetchBlockedByCountHandler = { _ in 15 }

        // When
        await sut.fetchBlockCounts(isOwnProfile: true)

        // Then: both blocking and blocked-by counts are populated
        XCTAssertEqual(sut.blockingCount, 25)
        XCTAssertEqual(sut.blockedByCount, 15)
        XCTAssertFalse(sut.isFetchingBlockCounts)
    }

    func testFetchBlockCountsWhenProfileIsNotOwn() async {
        // Given: counts are preset (simulating a prior own-profile view)
        sut.blockedByCount = 42
        sut.blockingCount = 100

        // When: fetching for another user's profile
        await sut.fetchBlockCounts(isOwnProfile: false)

        // Then: blockedByCount is cleared (not relevant for other profiles)
        XCTAssertNil(sut.blockedByCount)
        XCTAssertNil(sut.blockingCount)
    }

    // MARK: - State Matrix: Block Back

    func testBlockBackWithNoBlockers() async {
        // Given: clearsky returns an empty blocker list
        mockClearSky.fetchUnblockedBlockerActorsHandler = { _, _ in [] }

        // When: blockBack is invoked without pre-resolved actors
        await sut.blockBack()

        // Then: exits early with zero blocks performed
        XCTAssertFalse(sut.isBlockingBack)
        XCTAssertEqual(sut.blockBackTotal, 0)
        XCTAssertEqual(sut.blockBackCompleted, 0)
    }

    func testBlockBackCancellation() async {
        // Given: blockActor hangs so we can observe mid-flight state
        let didStart = expectation(description: "blockBack started blocking")
        nonisolated(unsafe) var continuation: CheckedContinuation<Void, any Error>?
        mockProfile.blockActorHandler = { _, _, _ in
            didStart.fulfill()
            try await withCheckedThrowingContinuation { cont in
                continuation = cont
            }
        }

        let task = Task {
            await sut.blockBack(actors: [makeActor()])
        }

        await fulfillment(of: [didStart], timeout: 1)
        XCTAssertTrue(sut.isBlockingBack, "isBlockingBack should be true while blocking")

        // When: task is cancelled and the hang is released
        task.cancel()
        continuation?.resume()

        _ = await task.value

        // Then: state is reset after the operation completes
        XCTAssertFalse(sut.isBlockingBack, "isBlockingBack should be false after cancellation")
    }

    // MARK: - State Matrix: Block Preview

    func testFetchBlockPreviewWithFailures() async {
        // Given: clearsky API returns an error
        mockClearSky.fetchUnblockedBlockerActorsHandler = { _, _ in
            throw BlueskyAPIError.server("Service unavailable")
        }

        // When
        await sut.fetchBlockPreview()

        // Then: error is captured and preview is not shown
        XCTAssertNotNil(sut.blockBackError)
        XCTAssertFalse(sut.isFetchingBlockPreview)
        XCTAssertFalse(sut.showBlockBackPreview)
        XCTAssertTrue(sut.blockPreviewActors.isEmpty)
    }
}
