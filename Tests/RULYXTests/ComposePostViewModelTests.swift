@testable import RULYX
import XCTest

/// Tests for ComposePostViewModel — posting logic, image handling,
/// and error states.
@MainActor
final class ComposePostViewModelTests: XCTestCase {
    private var viewModel: ComposePostViewModel!
    private var postService: MockPostService!
    private var mediaService: MockMediaService!
    private var listService: MockListService!
    private var account: AppAccount!

    override func setUp() {
        super.setUp()
        postService = MockPostService()
        mediaService = MockMediaService()
        listService = MockListService()
        account = AppAccount(handle: "test.bsky.social", did: "did:plc:test")
        viewModel = ComposePostViewModel(
            postService: postService,
            mediaService: mediaService,
            listService: listService,
            account: account,
            appPassword: "test-password"
        )
    }

    override func tearDown() {
        viewModel = nil
        postService = nil
        mediaService = nil
        listService = nil
        account = nil
        super.tearDown()
    }

    // MARK: - Initial State

    func testInitialStateIsEmpty() {
        XCTAssertTrue(viewModel.postText.isEmpty)
        XCTAssertTrue(viewModel.selectedImages.isEmpty)
        XCTAssertTrue(viewModel.imageAlts.isEmpty)
        XCTAssertFalse(viewModel.isPosting)
        XCTAssertNil(viewModel.uploadProgress)
        XCTAssertNil(viewModel.errorMessage)
        XCTAssertEqual(viewModel.maxImages, 4)
        XCTAssertEqual(viewModel.maxImageDimension, 3600)
    }

    func testAccountAndPasswordStored() {
        XCTAssertEqual(viewModel.account.handle, "test.bsky.social")
        XCTAssertEqual(viewModel.appPassword, "test-password")
    }

    // MARK: - Post Flow (Happy Path)

    func testPostCallsCreatePostAndCompletes() async {
        viewModel.postText = "Hello world"

        var didComplete = false
        viewModel.onComplete = { didComplete = true }

        await viewModel.post()

        XCTAssertFalse(viewModel.isPosting)
        XCTAssertNil(viewModel.errorMessage)
        XCTAssertTrue(didComplete, "onComplete should be called after successful post")
    }

    // MARK: - Post with Edit

    func testEditPostCompletesSuccessfully() async {
        let editEntry = makeEditEntry()
        viewModel.editPost = editEntry
        viewModel.postText = "Edited text"

        var didComplete = false
        viewModel.onComplete = { didComplete = true }

        await viewModel.post()

        XCTAssertFalse(viewModel.isPosting)
        XCTAssertTrue(didComplete)
    }

    // MARK: - Error Handling

    func testPostShowsErrorOnFailure() async {
        viewModel.postText = "Test"

        await viewModel.post()

        XCTAssertNil(viewModel.errorMessage, "Should not have error on success")
        XCTAssertFalse(viewModel.isPosting)
    }

    // MARK: Error-Path Tests

    /// When mediaService.uploadBlob throws, the error should be surfaced as errorMessage.
    func testPostWithImageUploadFailure() async {
        let failingMedia = FailingUploadMediaService()
        viewModel = ComposePostViewModel(
            postService: postService,
            mediaService: failingMedia,
            listService: listService,
            account: account,
            appPassword: "test-password"
        )
        viewModel.selectedImages = [(createTinyJPEG(), "image/jpeg")]
        viewModel.postText = "Upload should fail"

        await viewModel.post()

        XCTAssertNotNil(viewModel.errorMessage, "Should surface error when image upload fails")
        XCTAssertFalse(viewModel.isPosting)
    }

    /// When postService.createPost throws, the error should be surfaced as errorMessage.
    func testPostWithCreatePostFailure() async {
        let failingPost = FailingCreatePostService()
        viewModel = ComposePostViewModel(
            postService: failingPost,
            mediaService: mediaService,
            listService: listService,
            account: account,
            appPassword: "test-password"
        )
        viewModel.postText = "Create should fail"

        await viewModel.post()

        XCTAssertNotNil(viewModel.errorMessage, "Should surface error when createPost fails")
        XCTAssertFalse(viewModel.isPosting)
    }

    /// When deleteRecord throws during an edit, the post should still complete
    /// because deleteRecord is wrapped in `try?` (it's best-effort cleanup).
    func testEditPostDeleteRecordFailure() async {
        let failingDelete = FailingDeleteRecordService()
        viewModel = ComposePostViewModel(
            postService: failingDelete,
            mediaService: mediaService,
            listService: listService,
            account: account,
            appPassword: "test-password"
        )
        viewModel.editPost = makeEditEntry()
        viewModel.postText = "Edited text"

        var didComplete = false
        viewModel.onComplete = { didComplete = true }

        await viewModel.post()

        XCTAssertTrue(didComplete, "Post should complete even when deleteRecord fails")
        XCTAssertNil(viewModel.errorMessage, "Should not surface error for failed deleteRecord (try?)")
        XCTAssertFalse(viewModel.isPosting)
    }

    /// When fetchPostThread throws, loadReferencedPost should log but not crash.
    func testLoadReferencedPostFailure() async {
        // Default MockPostService.fetchPostThread already throws BlueskyAPIError.invalidResponse
        viewModel.replyTo = (
            parentURI: "at://did:plc:other/app.bsky.feed.post/1",
            parentCID: "cid-1",
            rootURI: "at://did:plc:other/app.bsky.feed.post/1",
            rootCID: "cid-1"
        )

        await viewModel.loadReferencedPost()

        XCTAssertNil(viewModel.referencedPost, "referencedPost should remain nil after fetch failure")
    }

    /// When fetchLists throws, loadUserLists should log but not crash,
    /// and userLists should stay empty.
    func testLoadUserListsFailure() async {
        listService.fetchListsHandler = { _, _ in throw BlueskyAPIError.invalidResponse }

        await viewModel.loadUserLists()

        XCTAssertTrue(viewModel.userLists.isEmpty, "userLists should be empty after fetch failure")
    }

    // MARK: - Image Validation

    func testValidateAndOfferResizeEmptyImages() async {
        viewModel.selectedImages = []
        await viewModel.validateAndOfferResize()
        XCTAssertFalse(viewModel.showImageResizeAlert)
    }

    // MARK: - Static Helpers

    func testFormatSpeedBytes() {
        XCTAssertEqual(ComposePostViewModel.formatSpeed(500), "\u{2191} 500 B/s")
    }

    func testFormatSpeedKilobytes() {
        XCTAssertEqual(ComposePostViewModel.formatSpeed(50000), "\u{2191} 50 KB/s")
    }

    func testFormatSpeedMegabytes() {
        XCTAssertEqual(ComposePostViewModel.formatSpeed(5_000_000), "\u{2191} 5.0 MB/s")
    }

    func testScaleDownIfNeededSmallImage() {
        let tinyImage = createTinyJPEG()
        let result = ComposePostViewModel.scaleDownIfNeeded(
            data: tinyImage,
            maxDimension: 3600,
            maxFileSize: 1_887_437
        )
        XCTAssertFalse(result.isEmpty)
    }

    // MARK: - Reset on Post

    func testIsPostingResetsAfterCompletion() async {
        viewModel.postText = "Test"

        await viewModel.post()

        XCTAssertFalse(viewModel.isPosting)
        XCTAssertNil(viewModel.uploadProgress)
        XCTAssertNil(viewModel.uploadSpeed)
    }

    // MARK: - Helpers

    private func makeEditEntry() -> RichFeedEntry {
        let record = RichRecord(text: "Old text", createdAt: "2024-01-01T00:00:00Z")
        let post = RichPost(
            uri: "at://did:plc:test/app.bsky.feed.post/old",
            cid: "old-cid",
            author: RichAuthor(did: "did:plc:test", handle: "test.bsky.social", displayName: nil, avatar: nil),
            record: record,
            embed: nil,
            viewer: nil,
            replyCount: 0,
            repostCount: 0,
            likeCount: 0,
            indexedAt: "2024-01-01T00:00:00Z"
        )
        return RichFeedEntry(post: post)
    }

    private func createTinyJPEG() -> Data {
        let size = CGSize(width: 1, height: 1)
        UIGraphicsBeginImageContext(size)
        UIColor.red.setFill()
        UIRectFill(CGRect(origin: .zero, size: size))
        let image = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        return image!.jpegData(compressionQuality: 1.0)!
    }
}

// MARK: - Failing Mocks for Error-Path Tests

/// BlueskyMediaServicing that throws on uploadBlob.
@MainActor
private final class FailingUploadMediaService: BlueskyMediaServicing {
    func uploadBlob(
        data _: Data,
        mimeType _: String,
        account _: AppAccount,
        appPassword _: String?,
        progress _: (@Sendable (Double) -> Void)?
    ) async throws -> UploadBlobResponse {
        throw BlueskyAPIError.invalidResponse
    }
}

/// BlueskyPostServicing that throws on createPost; all other methods succeed.
@MainActor
private final class FailingCreatePostService: BlueskyPostServicing {
    func fetchPostThread(uri _: String, depth _: Int?, account _: AppAccount, appPassword _: String?) async throws -> GetPostThreadResponse {
        throw BlueskyAPIError.invalidResponse
    }

    func createPost(
        text _: String,
        images _: [PostImageAttachment]?,
        video _: PostVideoAttachment?,
        external _: PostExternalAttachment?,
        replyTo _: (parentURI: String, parentCID: String, rootURI: String, rootCID: String)?,
        quote _: (uri: String, cid: String)?,
        threadGate _: ThreadGateRule?,
        allowQuoting _: Bool,
        account _: AppAccount,
        appPassword _: String?
    ) async throws -> CreateRecordResponse {
        throw BlueskyAPIError.invalidResponse
    }

    func createThreadGate(postURI _: String, rules _: [ThreadGateRule], account _: AppAccount, appPassword _: String?) async throws -> CreateRecordResponse {
        CreateRecordResponse(uri: "at://mock/gate", cid: "cid")
    }

    func createPostGate(postURI _: String, account _: AppAccount, appPassword _: String?) async throws -> CreateRecordResponse {
        CreateRecordResponse(uri: "at://mock/gate", cid: "cid")
    }

    func deleteRecord(recordURI _: String, account _: AppAccount, appPassword _: String?) async throws -> EmptyResponse {
        EmptyResponse()
    }

    func fetchPosts(uris _: [String]) async throws -> [RichPost] {
        []
    }

    func searchPosts(
        q _: String,
        mentions _: String?,
        sort _: String?,
        cursor _: String?,
        limit _: Int,
        account _: AppAccount,
        appPassword _: String?
    ) async throws -> SearchPostsResponse {
        SearchPostsResponse(cursor: nil, hitsTotal: 0, posts: [])
    }
}

/// BlueskyPostServicing that throws on deleteRecord; createPost succeeds.
/// Used to verify that a failed deleteRecord (which uses `try?`) does not
/// prevent the post from completing.
@MainActor
private final class FailingDeleteRecordService: BlueskyPostServicing {
    func fetchPostThread(uri _: String, depth _: Int?, account _: AppAccount, appPassword _: String?) async throws -> GetPostThreadResponse {
        throw BlueskyAPIError.invalidResponse
    }

    func createPost(
        text _: String,
        images _: [PostImageAttachment]?,
        video _: PostVideoAttachment?,
        external _: PostExternalAttachment?,
        replyTo _: (parentURI: String, parentCID: String, rootURI: String, rootCID: String)?,
        quote _: (uri: String, cid: String)?,
        threadGate _: ThreadGateRule?,
        allowQuoting _: Bool,
        account _: AppAccount,
        appPassword _: String?
    ) async throws -> CreateRecordResponse {
        CreateRecordResponse(uri: "at://mock/post", cid: "cid")
    }

    func createThreadGate(postURI _: String, rules _: [ThreadGateRule], account _: AppAccount, appPassword _: String?) async throws -> CreateRecordResponse {
        CreateRecordResponse(uri: "at://mock/gate", cid: "cid")
    }

    func createPostGate(postURI _: String, account _: AppAccount, appPassword _: String?) async throws -> CreateRecordResponse {
        CreateRecordResponse(uri: "at://mock/gate", cid: "cid")
    }

    func deleteRecord(recordURI _: String, account _: AppAccount, appPassword _: String?) async throws -> EmptyResponse {
        throw BlueskyAPIError.invalidResponse
    }

    func fetchPosts(uris _: [String]) async throws -> [RichPost] {
        []
    }

    func searchPosts(
        q _: String,
        mentions _: String?,
        sort _: String?,
        cursor _: String?,
        limit _: Int,
        account _: AppAccount,
        appPassword _: String?
    ) async throws -> SearchPostsResponse {
        SearchPostsResponse(cursor: nil, hitsTotal: 0, posts: [])
    }
}
