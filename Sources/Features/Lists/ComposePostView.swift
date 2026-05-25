import PhotosUI
import SwiftUI
import UIKit

struct ComposePostView: View {
    let account: AppAccount
    let appPassword: String
    let blueskyClient: LiveBlueskyClient
    let onComplete: () -> Void
    var replyTo: (parentURI: String, parentCID: String, rootURI: String, rootCID: String)?
    var quote: (uri: String, cid: String)?
    var placeholder: String?
    var editPost: RichFeedEntry?

    @Environment(\.dismiss) private var dismiss
    @State private var postText = ""
    @State private var selectedItems: [PhotosPickerItem] = []
    @State private var selectedImages: [(data: Data, mimeType: String)] = []
    @State private var imageAlts: [String] = []
    @State private var videoAttachment: PostVideoAttachment?
    @State private var selectedGIFPreviewURL: String?
    @State private var selectedGIFTitle: String = ""
    @State private var isPosting = false
    @State private var errorMessage: String?
    @State private var textViewRef: UITextView?
    @State private var referencedPost: ThreadPostNode?
    @State private var showGIFPicker = false
    @State private var isDownloadingGIF = false
    @State private var isPreloadingEdit = false
    @State private var editReplyTo: (parentURI: String, parentCID: String, rootURI: String, rootCID: String)?
    @State private var replyRule: ThreadGateRule?
    @State private var allowQuoting = true
    @State private var showReplyPicker = false
    @State private var showListPicker = false
    @State private var userLists: [BlueskyList] = []
    @State private var showImageResizeAlert = false
    @State private var pendingImageResize: (() -> Void)?
    @State private var isScaling = false

    private let maxImages = 4
    private let maxImageDimension: CGFloat = 3600
    private let maxImageFileSize = 1_887_437
    @EnvironmentObject private var localizationManager: LocalizationManager

    var body: some View {
        NavigationStack {
            List {
                let activeReplyTo = editReplyTo ?? replyTo
                if activeReplyTo != nil || quote != nil {
                    Section {
                        if let referencedPost {
                            postPreviewRow(referencedPost)
                        } else {
                            HStack {
                                ProgressView()
                                    .scaleEffect(0.8)
                                Text(loc: "timeline.loading")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    } header: {
                        Text(verbatim: activeReplyTo != nil ? loc("profile.posts.replying_to") : loc("compose.quoting"))
                    }
                }

                Section {
                    WritingToolsTextView(text: $postText, textViewRef: $textViewRef)
                        .frame(minHeight: 120)

                    HStack {
                        Spacer()
                        if postText.count > 300 {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                        Text("\(postText.count)/300")
                            .font(.caption)
                            .foregroundStyle(postText.count > 300 ? .red : .green)
                    }
                    .accessibilityLabel(loc("compose.char_count").replacingOccurrences(of: "{n}", with: "\(postText.count)/300"))
                } header: {
                    Text(loc: "compose.text_section")
                }

                if let previewURL = selectedGIFPreviewURL, !previewURL.isEmpty {
                    Section {
                        VStack(alignment: .leading, spacing: 8) {
                            AsyncImage(url: URL(string: previewURL)) { image in
                                image
                                    .resizable()
                                    .scaledToFit()
                                    .frame(maxHeight: 160)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                            } placeholder: {
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(.quaternary)
                                    .frame(height: 120)
                            }
                            if !selectedGIFTitle.isEmpty {
                                Text(selectedGIFTitle)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Button(role: .destructive) {
                                videoAttachment = nil
                                selectedGIFPreviewURL = nil
                                selectedGIFTitle = ""
                            } label: {
                                Label("actions.remove", systemImage: "xmark.circle.fill")
                                    .font(.caption)
                            }
                        }
                    } header: {
                        Text(loc: "compose.gif_selected")
                    }
                }

                imageAttachmentsSection

                replyControlsSection
                addMediaSection
            }
            .navigationTitle(navigationTitleString)
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("actions.cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("compose.post") {
                        Task { await post() }
                    }
                    .disabled(postText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isPosting)
                }
            }
            .alert(Text(loc: "compose.error"), isPresented: .constant(errorMessage != nil)) {
                Button("actions.ok") { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
            .sheet(isPresented: $showGIFPicker) {
                GIFPickerView { gif in
                    Task { await handleGIFSelection(gif) }
                }
            }
            .confirmationDialog(loc("compose.reply_controls"), isPresented: $showReplyPicker) {
                Button(loc("compose.reply_everyone")) { replyRule = nil }
                Button(loc("compose.reply_nobody")) { replyRule = .noReply }
                Button(loc("compose.reply_following")) { replyRule = .followingRule }
                Button(loc("compose.reply_mention")) { replyRule = .mentionRule }
                Button(loc("compose.reply_list")) {
                    showListPicker = true
                    Task { await loadUserLists() }
                }
                Button("actions.cancel", role: .cancel) {}
            }
            .sheet(isPresented: $showListPicker) {
                NavigationStack {
                    List(userLists) { list in
                            Button {
                                if let cid = list.cid {
                                    replyRule = .listRule(list: list.id)
                                }
                                showListPicker = false
                            } label: {
                                listRowLabel(list)
                            }
                    }
                    .navigationTitle(loc("compose.reply_list_pick"))
                    .toolbarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("actions.cancel") { showListPicker = false }
                        }
                    }
                }
            }
            .overlay {
                if isScaling {
                    ZStack {
                        Color.black.opacity(0.3)
                            .ignoresSafeArea()
                        VStack(spacing: 16) {
                            ProgressView()
                                .scaleEffect(1.5)
                            Text(loc("compose.image_scaling"))
                                .font(.headline)
                                .foregroundStyle(.white)
                        }
                        .padding(24)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                    }
                    .transition(.opacity.animation(.easeInOut(duration: 0.2)))
                }
            }
            .alert(loc("compose.image_resize_title"), isPresented: $showImageResizeAlert, presenting: pendingImageResize) { _ in
                Button(loc("compose.image_resize_scale")) {
                    pendingImageResize?()
                    showImageResizeAlert = false
                }
                Button("actions.cancel", role: .cancel) {
                    showImageResizeAlert = false
                }
            } message: { _ in
                Text(loc("compose.image_resize_message"))
            }
            .task {
                await loadReferencedPost()
                await preloadEditData()
            }
        }
    }

    @ViewBuilder private var imageAttachmentsSection: some View {
        if !selectedImages.isEmpty {
            Section {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(Array(selectedImages.enumerated()), id: \.offset) { index, image in
                            let altBinding = Binding(
                                get: { index < imageAlts.count ? imageAlts[index] : "" },
                                set: { if index < imageAlts.count { imageAlts[index] = $0 } }
                            )
                            VStack(spacing: 4) {
                                ZStack(alignment: .topTrailing) {
                                    if let uiImage = UIImage(data: image.data) {
                                        Image(uiImage: uiImage)
                                            .resizable()
                                            .scaledToFill()
                                            .frame(width: 100, height: 100)
                                            .clipShape(RoundedRectangle(cornerRadius: 8))
                                    }
                                    Button {
                                        selectedImages.remove(at: index)
                                        imageAlts.remove(at: index)
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .font(.title3)
                                            .foregroundStyle(.red)
                                            .background(Circle().fill(.ultraThinMaterial).frame(width: 24, height: 24))
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel(loc("compose.remove_image"))
                                    .frame(minWidth: 44, minHeight: 44)
                                    .contentShape(Rectangle())
                                    .offset(x: 4, y: -4)
                                }
                                TextField("compose.alt_placeholder", text: altBinding)
                                    .font(.caption)
                                    .textFieldStyle(.plain)
                                    .frame(width: 100)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
            } header: {
                Text(loc: "compose.images_section")
            }
        }
    }

    private var replyControlsSection: some View {
        Section {
            Label {
                HStack {
                    Text(loc("compose.reply_controls"))
                    Spacer()
                    Text(replyRuleLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            } icon: {
                Image(systemName: "arrowshape.turn.up.right.circle")
            }
            .contentShape(Rectangle())
            .onTapGesture { showReplyPicker = true }

            Toggle(loc("compose.allow_quoting"), isOn: $allowQuoting)
        }
    }

    private var addMediaSection: some View {
        Section {
            PhotosPicker(selection: $selectedItems, maxSelectionCount: maxImages, matching: .images) {
                Label { Text(loc: "compose.add_images") } icon: { Image(systemName: "photo.on.rectangle.angled") }
            }
            .disabled(selectedImages.count >= maxImages || videoAttachment != nil)
            .onChange(of: selectedItems) { _, items in
                Task { await loadImages(from: items) }
            }

            Button {
                showGIFPicker = true
            } label: {
                HStack {
                    Label { Text(loc: "compose.add_gif") } icon: { Image(systemName: "play.rectangle") }
                    Spacer()
                    if isDownloadingGIF {
                        ProgressView()
                            .scaleEffect(0.7)
                    }
                }
            }
            .disabled(videoAttachment != nil || !selectedImages.isEmpty)
            .foregroundStyle(videoAttachment != nil ? Color.skyPrimary : .primary)
        }
    }

    private func postPreviewRow(_ post: ThreadPostNode) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            let author = post.author ?? RichAuthor(did: "", handle: "unknown", displayName: nil, avatar: nil)
            PostAuthorHeader(
                author: author,
                createdAt: post.indexedAt ?? post.record?.createdAt,
                onOpenProfile: nil,
                avatarSize: 24
            )
            if let text = post.record?.text, !text.isEmpty {
                PostTextContent(
                    text: text,
                    lineLimit: 6
                )
            }
        }
    }

    private var navigationTitleString: String {
        if editPost != nil { return loc("post.edit") }
        if (editReplyTo ?? replyTo) != nil { return loc("compose.reply_title") }
        if quote != nil { return loc("compose.quote_title") }
        return loc("compose.title")
    }

    private var replyRuleLabel: String {
        guard let replyRule else { return loc("compose.reply_everyone") }
        switch replyRule {
        case .noReply: return loc("compose.reply_nobody")
        case .mentionRule: return loc("compose.reply_mention")
        case .followingRule: return loc("compose.reply_following")
        case .listRule: return loc("compose.reply_list")
        }
    }

    private var replyRuleListID: String? {
        if case let .listRule(list) = replyRule { return list }
        return nil
    }

    private func listRowLabel(_ list: BlueskyList) -> some View {
        HStack {
            Image(systemName: list.kind.symbolName)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(list.name)
                    .foregroundStyle(.primary)
                if let count = list.memberCount {
                    let members = loc("compose.reply_list_count").replacingOccurrences(of: "{n}", with: "\(count)")
                    Text(verbatim: members)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if case .listRule = replyRule, list.id == replyRuleListID {
                Image(systemName: "checkmark")
            }
        }
    }

    private func loadReferencedPost() async {
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
            let response = try await blueskyClient.fetchPostThread(uri: uri, account: account, appPassword: appPassword)
            referencedPost = response.thread.post
        } catch {
            AppLogger.moderation.error("Failed to load referenced post: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func preloadEditData() async {
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
                    AppLogger.moderation.error("Failed to download image for edit: \(error.localizedDescription, privacy: .public)")
                }
            }
        }

        if editReplyTo == nil, let reply = editPost.reply, let rootURI = reply.root?.uri, let rootCID = reply.root?.cid,
           let parentURI = reply.parent?.uri, let parentCID = reply.parent?.cid {
            editReplyTo = (parentURI, parentCID, rootURI, rootCID)
        }
    }

    private func loadUserLists() async {
        guard userLists.isEmpty else { return }
        do {
            userLists = try await blueskyClient.fetchLists(for: account, appPassword: appPassword)
        } catch {
            AppLogger.moderation.error("Failed to load lists: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func loadImages(from items: [PhotosPickerItem]) async {
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

    private func validateAndOfferResize() async {
        guard !selectedImages.isEmpty else { return }
        let needsResize = selectedImages.contains { data, _ in
            data.count > maxImageFileSize || imageExceedsMaxDimension(data)
        }
        if needsResize {
            pendingImageResize = { Task { await scaleDownImages() } }
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

    @MainActor
    private func scaleDownImages() {
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

    private static func scaleDownIfNeeded(data: Data, maxDimension: CGFloat, maxFileSize: Int) -> Data {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return data }

        let targetType = "public.jpeg" as CFString
        var currentMax = Int(maxDimension)
        var result = data

        for _ in 0..<5 {
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
                if compressed.count <= maxFileSize, fitsDimensions { return compressed }
                quality -= 0.1
            }

            result = compressed

            let maxSide = max(tw, th)
            if maxSide <= Int(maxDimension), compressed.count <= maxFileSize { return compressed }
            if currentMax <= 500 { return result }
            currentMax = Int(CGFloat(currentMax) * 0.85)
        }

        return result
    }

    private func handleGIFSelection(_ gif: GIFResult) async {
        guard !gif.mp4URL.isEmpty else { return }
        isDownloadingGIF = true
        selectedGIFPreviewURL = gif.previewURL
        selectedGIFTitle = gif.title
        defer { isDownloadingGIF = false }
        do {
            let data = try await GIFService.shared.downloadGIF(url: gif.mp4URL)
            let response = try await blueskyClient.uploadBlob(
                data: data,
                mimeType: "video/mp4",
                account: account,
                appPassword: appPassword
            )
            let ratio: (width: Int, height: Int)? = gif.width > 0 && gif.height > 0 ? (gif.width, gif.height) : nil
            videoAttachment = PostVideoAttachment(blob: response.blob, alt: gif.title, aspectRatio: ratio)
        } catch {
            videoAttachment = nil
            selectedGIFPreviewURL = nil
            selectedGIFTitle = ""
            errorMessage = error.localizedDescription
        }
    }

    private func post() async {
        isPosting = true
        defer { isPosting = false }
        do {
            let images: [PostImageAttachment]?
            if selectedImages.isEmpty {
                images = nil
            } else {
                var result: [PostImageAttachment] = []
                for (index, image) in selectedImages.enumerated() {
                    let blob = try await blueskyClient.uploadBlob(
                        data: image.data,
                        mimeType: image.mimeType,
                        account: account,
                        appPassword: appPassword
                    )
                    let alt = imageAlts[safe: index] ?? ""
                    result.append(PostImageAttachment(blob: blob.blob, alt: alt))
                }
                images = result
            }
            _ = try await blueskyClient.createPost(
                text: postText,
                images: images,
                video: videoAttachment,
                replyTo: editReplyTo ?? replyTo,
                quote: quote,
                threadGate: replyRule,
                allowQuoting: allowQuoting,
                account: account,
                appPassword: appPassword
            )

            if let editPost {
                try? await blueskyClient.deleteRecord(
                    recordURI: editPost.post.uri,
                    account: account,
                    appPassword: appPassword
                )
            }

            onComplete()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - WritingTools UITextView Wrapper

private struct WritingToolsTextView: UIViewRepresentable {
    @Binding var text: String
    @Binding var textViewRef: UITextView?

    func makeUIView(context: Context) -> UITextView {
        let tv = UITextView()
        tv.font = .preferredFont(forTextStyle: .body)
        tv.backgroundColor = .clear
        tv.delegate = context.coordinator
        tv.isScrollEnabled = false
        tv.textContainerInset = UIEdgeInsets(top: 8, left: 4, bottom: 8, right: 4)
        tv.textContainer.lineBreakMode = .byWordWrapping
        return tv
    }

    func updateUIView(_ uiView: UITextView, context _: Context) {
        if uiView.text != text {
            uiView.text = text
        }
        textViewRef = uiView
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextView, context _: Context) -> CGSize? {
        guard let width = proposal.width, width > 0 else { return nil }
        let fittingSize = CGSize(width: width, height: UIView.layoutFittingExpandedSize.height)
        let size = uiView.sizeThatFits(fittingSize)
        return CGSize(width: width, height: max(size.height, 120))
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        @Binding var text: String
        init(text: Binding<String>) {
            _text = text
        }

        func textViewDidChange(_ textView: UITextView) {
            text = textView.text
        }
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

private extension Data {
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
