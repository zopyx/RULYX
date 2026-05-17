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

    private let maxImages = 4
    @MainActor private static var addImagesLabel: String {
        loc("compose.add_images")
    }

    var body: some View {
        NavigationStack {
            List {
                if replyTo != nil || quote != nil {
                    Section {
                        if let referencedPost {
                            postPreviewRow(referencedPost)
                        } else {
                            HStack {
                                ProgressView()
                                    .scaleEffect(0.8)
                                Text(verbatim: loc("timeline.loading"))
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    } header: {
                        Text(verbatim: replyTo != nil ? loc("profile.posts.replying_to") : loc("compose.quoting"))
                    }
                }

                Section {
                    WritingToolsTextView(text: $postText, textViewRef: $textViewRef)
                        .frame(minHeight: 120)

                    HStack {
                        Spacer()
                        Text("\(postText.count)/300")
                            .font(.caption)
                            .foregroundStyle(postText.count > 300 ? .red : .green)
                    }
                } header: {
                    Text(verbatim: loc("compose.text_section"))
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
                                Label(loc("actions.remove"), systemImage: "xmark.circle.fill")
                                    .font(.caption)
                            }
                        }
                    } header: {
                        Text(verbatim: loc("compose.gif_selected"))
                    }
                }

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
                                        if let uiImage = UIImage(data: image.data) {
                                            Image(uiImage: uiImage)
                                                .resizable()
                                                .scaledToFill()
                                                .frame(width: 100, height: 100)
                                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                        }
                                        TextField(loc("compose.alt_placeholder"), text: altBinding)
                                            .font(.caption)
                                            .textFieldStyle(.plain)
                                            .frame(width: 100)
                                        Button {
                                            selectedImages.remove(at: index)
                                            imageAlts.remove(at: index)
                                        } label: {
                                            Label { Text(verbatim: loc("actions.remove")) } icon: { Image(systemName: "xmark.circle.fill") }
                                                .font(.caption)
                                                .foregroundStyle(.red)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    } header: {
                        Text(verbatim: loc("compose.images_section"))
                    }
                }

                Section {
                    PhotosPicker(selection: $selectedItems, maxSelectionCount: maxImages, matching: .images) {
                        Label { Text(verbatim: Self.addImagesLabel) } icon: { Image(systemName: "photo.on.rectangle.angled") }
                    }
                    .disabled(selectedImages.count >= maxImages || videoAttachment != nil)
                    .onChange(of: selectedItems) { _, items in
                        Task { await loadImages(from: items) }
                    }

                    Button {
                        showGIFPicker = true
                    } label: {
                        HStack {
                            Label { Text(verbatim: loc("compose.add_gif")) } icon: { Image(systemName: "play.rectangle") }
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
            .navigationTitle(replyTo != nil ? loc("compose.reply_title") : (quote != nil ? loc("compose.quote_title") : loc("compose.title")))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(loc("actions.cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(loc("compose.post")) {
                        Task { await post() }
                    }
                    .disabled(postText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isPosting)
                }
            }
            .alert(loc("compose.error"), isPresented: .constant(errorMessage != nil)) {
                Button(loc("actions.ok")) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
            .sheet(isPresented: $showGIFPicker) {
                GIFPickerView { gif in
                    Task { await handleGIFSelection(gif) }
                }
            }
            .task {
                await loadReferencedPost()
            }
        }
    }

    private func postPreviewRow(_ post: ThreadPostNode) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                if let avatarURL = post.author?.avatar, let url = URL(string: avatarURL) {
                    AsyncImage(url: url) { image in
                        image.resizable().scaledToFill()
                    } placeholder: {
                        Circle().fill(.quaternary)
                    }
                    .frame(width: 24, height: 24)
                    .clipShape(Circle())
                } else {
                    Circle()
                        .fill(.quaternary)
                        .frame(width: 24, height: 24)
                }
                Text(post.author?.displayName ?? post.author?.handle ?? "")
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                if let handle = post.author?.handle {
                    Text("@\(handle)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            if let text = post.record?.text, !text.isEmpty {
                Text(text)
                    .font(.body)
                    .lineLimit(6)
                    .foregroundStyle(.primary)
            }
        }
    }

    private func loadReferencedPost() async {
        let uri: String
        if let replyTo {
            uri = replyTo.parentURI
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

    private func loadImages(from items: [PhotosPickerItem]) async {
        var newImages: [(Data, String)] = []
        var newAlts: [String] = []
        for item in items {
            if let data = try? await item.loadTransferable(type: Data.self) {
                let mimeType = item.supportedContentTypes.first?.preferredMIMEType ?? "image/jpeg"
                newImages.append((data, mimeType))
                newAlts.append("")
            }
        }
        selectedImages = Array(newImages.prefix(maxImages))
        imageAlts = Array(newAlts.prefix(maxImages))
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
                replyTo: replyTo,
                quote: quote,
                account: account,
                appPassword: appPassword
            )
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
