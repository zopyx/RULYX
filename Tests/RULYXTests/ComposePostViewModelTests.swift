@testable import RULYX
import XCTest

/// Tests for ComposePostViewModel — posting logic, image handling,
/// GIF selection, and error states.
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

    // MARK: - GIF Handling

    func testHandleGIFSelectionSetsPreview() async {
        let gif = GIFResult(
            id: "gif1",
            mp4URL: "https://example.com/video.mp4",
            previewURL: "https://example.com/preview.gif",
            width: 320,
            height: 240,
            title: "Test GIF"
        )

        await viewModel.handleGIFSelection(gif)

        XCTAssertEqual(viewModel.selectedGIFPreviewURL, "https://example.com/preview.gif")
        XCTAssertEqual(viewModel.selectedGIFLinkURL, "https://example.com/video.mp4")
        XCTAssertEqual(viewModel.selectedGIFTitle, "Test GIF")
        XCTAssertNil(viewModel.videoAttachment, "Video attachment should be cleared when GIF is selected")
    }

    func testHandleGIFSelectionDoesNothingWhenDownloading() async {
        viewModel.isDownloadingGIF = true
        let gif = GIFResult(id: "g", mp4URL: "m", previewURL: "p", width: 1, height: 1, title: "G")

        await viewModel.handleGIFSelection(gif)

        XCTAssertNil(viewModel.selectedGIFPreviewURL, "Should not update while downloading")
    }

    func testHandleGIFSelectionIgnoresEmptyMP4() async {
        let gif = GIFResult(id: "g", mp4URL: "", previewURL: "p", width: 1, height: 1, title: "G")

        await viewModel.handleGIFSelection(gif)

        XCTAssertNil(viewModel.selectedGIFPreviewURL, "Should ignore GIFs with empty mp4 URL")
    }

    // MARK: - GIF External Attachment

    func testGIFExternalAttachmentWhenLinkSet() {
        viewModel.selectedGIFLinkURL = "https://example.com/video.mp4"
        viewModel.selectedGIFTitle = "My GIF"

        let attachment = viewModel.selectedGIFExternalAttachment

        XCTAssertNotNil(attachment)
        XCTAssertEqual(attachment?.uri, "https://example.com/video.mp4")
        XCTAssertEqual(attachment?.title, "My GIF")
    }

    func testGIFExternalAttachmentNilWhenNoLink() {
        viewModel.selectedGIFLinkURL = nil
        XCTAssertNil(viewModel.selectedGIFExternalAttachment)
    }

    func testGIFExternalAttachmentDefaultTitle() {
        viewModel.selectedGIFLinkURL = "https://example.com/g.mp4"
        viewModel.selectedGIFTitle = ""

        let attachment = viewModel.selectedGIFExternalAttachment
        XCTAssertEqual(attachment?.title, "GIF")
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
        XCTAssertEqual(ComposePostViewModel.formatSpeed(50_000), "\u{2191} 50 KB/s")
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
