import Observation
import PhotosUI
import SwiftUI
import UIKit

/// View model for ComposePostView — handles all posting state and async logic.
/// Extracted from the view to enable isolated unit testing with protocol-typed
/// service injection.
@MainActor
@Observable
final class ComposePostViewModel {
    // MARK: - Dependencies

    private let postService: BlueskyPostServicing
    private let mediaService: BlueskyMediaServicing
    private let listService: BlueskyListServicing
    let account: AppAccount
    let appPassword: String

    // MARK: - Input configuration

    var onComplete: (() -> Void)?
    var replyTo: (parentURI: String, parentCID: String, rootURI: String, rootCID: String)?
    var quote: (uri: String, cid: String)?
    var placeholder: String?
    var editPost: RichFeedEntry?

    // MARK: - Published state

    var postText = ""
    var selectedItems: [PhotosPickerItem] = []
    var selectedImages: [(data: Data, mimeType: String)] = []
    var imageAlts: [String] = []
    var videoAttachment: PostVideoAttachment?
    var isPosting = false
    var uploadProgress: Double?
    var uploadSpeed: String?
    var errorMessage: String?
    var referencedPost: ThreadPostNode?
    var loadError: String?
    var isPreloadingEdit = false
    var editReplyTo: (parentURI: String, parentCID: String, rootURI: String, rootCID: String)?
    var replyRule: ThreadGateRule?
    var allowQuoting = true
    var showReplyPicker = false
    var showListPicker = false
    var userLists: [BlueskyList] = []
    var showImageResizeAlert = false
    var pendingImageResize: (() -> Void)?
    var isScaling = false
    var altEditIndex: Int?

    // MARK: - Constants

    let maxImages = 4
    let maxImageDimension: CGFloat = 3600
    let maxImageFileSize = 1_887_437

    // MARK: - Init

    init(
        postService: BlueskyPostServicing,
        mediaService: BlueskyMediaServicing,
        listService: BlueskyListServicing,
        account: AppAccount,
        appPassword: String,
        onComplete: (() -> Void)? = nil,
        replyTo: (parentURI: String, parentCID: String, rootURI: String, rootCID: String)? = nil,
        quote: (uri: String, cid: String)? = nil,
        placeholder: String? = nil,
        editPost: RichFeedEntry? = nil
    ) {
        self.postService = postService
        self.mediaService = mediaService
        self.listService = listService
        self.account = account
        self.appPassword = appPassword
        self.onComplete = onComplete
        self.replyTo = replyTo
        self.quote = quote
        self.placeholder = placeholder
        self.editPost = editPost
    }

    /// Convenience initializer using the live client (for transition period).
    convenience init(
        blueskyClient: LiveBlueskyClient,
        account: AppAccount,
        appPassword: String,
        onComplete: (() -> Void)? = nil,
        replyTo: (parentURI: String, parentCID: String, rootURI: String, rootCID: String)? = nil,
        quote: (uri: String, cid: String)? = nil,
        placeholder: String? = nil,
        editPost: RichFeedEntry? = nil
    ) {
        self.init(
            postService: blueskyClient,
            mediaService: blueskyClient,
            listService: blueskyClient,
            account: account,
            appPassword: appPassword,
            onComplete: onComplete,
            replyTo: replyTo,
            quote: quote,
            placeholder: placeholder,
            editPost: editPost
        )
    }

    // MARK: - Post loading

    func loadReferencedPost() async {
        let activeReplyTo = editReplyTo ?? replyTo
        let uri: String
        if let activeReplyTo {
            uri = activeReplyTo.parentURI
        } else if let quote {
            uri = quote.uri
        } else {
            return
        }
        do {
            let response = try await postService.fetchPostThread(uri: uri, depth: nil, account: account, appPassword: appPassword)
            referencedPost = response.thread.post
        } catch {
            loadError = AppError.userMessage(from: error)
            AppLogger.moderation.error("Failed to load referenced post: \(error.localizedDescription, privacy: .private)")
        }
    }

    func preloadEditData() async {
        guard let editPost, isPreloadingEdit == false else { return }
        isPreloadingEdit = true
        defer { isPreloadingEdit = false }

        if let text = editPost.post.record?.text {
            postText = text
        }

        if let images = editPost.post.embed?.images {
            for img in images {
                guard let fullsize = img.fullsize,
                      let url = URL(string: fullsize),
                      selectedImages.count < maxImages
                else { continue }
                do {
                    let (data, _) = try await URLSession.shared.data(from: url)
                    let mimeType = fullsize.hasSuffix(".png") ? "image/png" : "image/jpeg"
                    let stripped = data.strippingLocationMetadata()
                    selectedImages.append((stripped, mimeType))
                    imageAlts.append(img.alt ?? "")
                } catch {
                    AppLogger.moderation.error("Failed to download image for edit: \(error.localizedDescription, privacy: .private)")
                }
            }
        }

        if editReplyTo == nil, let reply = editPost.reply, let rootURI = reply.root?.uri, let rootCID = reply.root?.cid,
           let parentURI = reply.parent?.uri, let parentCID = reply.parent?.cid
        {
            editReplyTo = (parentURI, parentCID, rootURI, rootCID)
        }
    }

    func loadUserLists() async {
        guard userLists.isEmpty else { return }
        do {
            userLists = try await listService.fetchLists(for: account, appPassword: appPassword)
        } catch {
            AppLogger.moderation.error("Failed to load lists: \(error.localizedDescription, privacy: .private)")
        }
    }

    // MARK: - Image handling

    func loadImages(from items: [PhotosPickerItem]) async {
        var newImages: [(Data, String)] = []
        var newAlts: [String] = []
        for item in items {
            if let data = try? await item.loadTransferable(type: Data.self) {
                let mimeType = item.supportedContentTypes.first?.preferredMIMEType ?? "image/jpeg"
                newImages.append((data.strippingLocationMetadata(), mimeType))
                newAlts.append("")
            }
        }
        selectedImages = Array(newImages.prefix(maxImages))
        imageAlts = Array(newAlts.prefix(maxImages))
        await validateAndOfferResize()
    }

    func validateAndOfferResize() async {
        guard !selectedImages.isEmpty else { return }
        let needsResize = selectedImages.contains { data, _ in
            data.count > maxImageFileSize || imageExceedsMaxDimension(data)
        }
        if needsResize {
            pendingImageResize = { [weak self] in self?.scaleDownImages() }
            showImageResizeAlert = true
        }
    }

    private func imageExceedsMaxDimension(_ data: Data) -> Bool {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any]
        else { return false }
        let w = props[kCGImagePropertyPixelWidth as String] as? CGFloat ?? 0
        let h = props[kCGImagePropertyPixelHeight as String] as? CGFloat ?? 0
        return max(w, h) > maxImageDimension
    }

    func scaleDownImages() {
        isScaling = true
        var scaled: [(Data, String)] = []
        var alts: [String] = []
        for (index, image) in selectedImages.enumerated() {
            let (data, _) = image
            let scaledData = Self.scaleDownIfNeeded(data: data, maxDimension: maxImageDimension, maxFileSize: maxImageFileSize)
            scaled.append((scaledData, "image/jpeg"))
            alts.append(imageAlts[safe: index] ?? "")
        }
        selectedImages = scaled
        imageAlts = alts
        isScaling = false
    }

    static func scaleDownIfNeeded(data: Data, maxDimension: CGFloat, maxFileSize: Int) -> Data {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return data }

        let targetType = "public.jpeg" as CFString
        var currentMax = Int(maxDimension)
        var result = data

        for _ in 0 ..< 5 {
            let opts: [CFString: Any] = [
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: currentMax,
            ]
            guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, opts as CFDictionary)
            else { return result }

            let tw = thumbnail.width
            let th = thumbnail.height
            let fitsDimensions = max(tw, th) <= Int(maxDimension)

            var quality: CGFloat = 0.9
            var compressed = result

            while quality > 0.1 {
                let mutableData = NSMutableData()
                guard let dest = CGImageDestinationCreateWithData(mutableData as CFMutableData, targetType, 1, nil)
                else { break }
                let props: NSDictionary = [kCGImageDestinationLossyCompressionQuality: quality]
                CGImageDestinationAddImage(dest, thumbnail, props)
                guard CGImageDestinationFinalize(dest) else { break }
                compressed = mutableData as Data
                if compressed.count <= maxFileSize, fitsDimensions {
                    return compressed
                }
                quality -= 0.1
            }

            result = compressed

            let maxSide = max(tw, th)
            if maxSide <= Int(maxDimension), compressed.count <= maxFileSize {
                return compressed
            }
            if currentMax <= 500 {
                return result
            }
            currentMax = Int(CGFloat(currentMax) * 0.85)
        }

        return result
    }

    // MARK: - Posting

    func post() async {
        isPosting = true
        uploadProgress = nil
        uploadSpeed = nil
        defer {
            isPosting = false
            uploadProgress = nil
            uploadSpeed = nil
        }
        do {
            let images: [PostImageAttachment]?
            if selectedImages.isEmpty {
                images = nil
            } else {
                let totalBytes = selectedImages.reduce(0) { $0 + $1.data.count }
                let startTime = Date()
                var result: [PostImageAttachment] = []
                for (index, image) in selectedImages.enumerated() {
                    let imageBytes = image.data.count
                    let startOffset = result.reduce(0) { $0 + $1.blob.size }
                    let blob = try await mediaService.uploadBlob(
                        data: image.data,
                        mimeType: image.mimeType,
                        account: account,
                        appPassword: appPassword,
                        progress: { [startOffset, imageBytes, totalBytes, startTime] fraction in
                            let totalUploaded = Double(startOffset) + Double(imageBytes) * fraction
                            let overallProgress = totalUploaded / Double(totalBytes)
                            let elapsed = max(startTime.timeIntervalSinceNow * -1, 0.001)
                            let bytesPerSec = totalUploaded / elapsed
                            Task { @MainActor [weak self] in
                                self?.uploadProgress = overallProgress
                                self?.uploadSpeed = Self.formatSpeed(bytesPerSec)
                            }
                        }
                    )
                    let alt = imageAlts[safe: index] ?? ""
                    result.append(PostImageAttachment(blob: blob.blob, alt: alt))
                    let overallProgress = Double(result.reduce(0) { $0 + $1.blob.size }) / Double(totalBytes)
                    uploadProgress = overallProgress
                }
                images = result
            }
            _ = try await postService.createPost(
                text: postText,
                images: images,
                video: videoAttachment,
                external: nil,
                replyTo: editReplyTo ?? replyTo,
                quote: quote,
                threadGate: replyRule,
                allowQuoting: allowQuoting,
                account: account,
                appPassword: appPassword
            )

            if let editPost {
                _ = try? await postService.deleteRecord(
                    recordURI: editPost.post.uri,
                    account: account,
                    appPassword: appPassword
                )
            }

            onComplete?()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Static helpers

    static func formatSpeed(_ bytesPerSecond: Double) -> String {
        if bytesPerSecond >= 1_000_000 {
            String(format: "\u{2191} %.1f MB/s", bytesPerSecond / 1_000_000)
        } else if bytesPerSecond >= 1000 {
            String(format: "\u{2191} %.0f KB/s", bytesPerSecond / 1000)
        } else {
            String(format: "\u{2191} %.0f B/s", bytesPerSecond)
        }
    }
}

// MARK: - Helper Extensions

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

extension Data {
    func strippingLocationMetadata() -> Data {
        guard let source = CGImageSourceCreateWithData(self as CFData, nil),
              let type = CGImageSourceGetType(source),
              let metadata = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any],
              metadata.keys.contains(kCGImagePropertyGPSDictionary as String)
        else { return self }
        let mutableMetadata = NSMutableDictionary(dictionary: metadata)
        mutableMetadata.removeObject(forKey: kCGImagePropertyGPSDictionary)
        let destinationData = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(destinationData as CFMutableData, type, 1, nil)
        else { return self }
        CGImageDestinationAddImageFromSource(destination, source, 0, mutableMetadata as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return self }
        return destinationData as Data
    }
}
