import PhotosUI
import SwiftUI

// MARK: - ReplyComposerView

/// Composes a reply to a post — shows the parent post preview, a text editor
/// with character count, optional images, and posts via the Bluesky API.
@MainActor
struct ReplyComposerView: View {
    let account: AppAccount
    let appPassword: String
    /// The reply flow only needs post and media capabilities.  Keeping this
    /// dependency protocol-based allows previews and tests to supply a
    /// lightweight implementation without coupling the view to the concrete
    /// production client.
    let blueskyClient: any BlueskyPostServicing & BlueskyMediaServicing
    let parentURI: String
    let parentCID: String
    let rootURI: String
    let rootCID: String
    var onComplete: (() -> Void)?

    @Environment(\.dismiss) private var dismiss
    @State private var postText = ""
    @State private var isPosting = false
    @State private var parentPost: RichPost?
    @State private var errorMessage: String?
    @State private var profileToShow: BlueskyActor?

    // Media attachments
    @State private var selectedItems: [PhotosPickerItem] = []
    @State private var selectedImages: [(data: Data, mimeType: String)] = []

    private let maxImages = 4
    private let maxChars = 300

    // MARK: - Body

    var body: some View {
        let addImagesLabel = loc("compose.add_images")
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    if let parentPost {
                        parentPreview(parentPost)
                    }

                    TextEditor(text: $postText)
                        .font(.body)
                        .scrollContentBackground(.hidden)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .frame(minHeight: 100)
                        .overlay(alignment: .topLeading) {
                            if postText.isEmpty {
                                Text(loc("compose.placeholder"))
                                    .font(.body)
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 20)
                                    .padding(.vertical, 14)
                                    .allowsHitTesting(false)
                            }
                        }

                    if !selectedImages.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 12) {
                                ForEach(Array(selectedImages.enumerated()), id: \.offset) { index, img in
                                    ZStack(alignment: .topTrailing) {
                                        if let uiImage = UIImage(data: img.data) {
                                            Image(uiImage: uiImage)
                                                .resizable()
                                                .scaledToFill()
                                                .frame(width: 80, height: 80)
                                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                        }
                                        Button {
                                            selectedImages.remove(at: index)
                                        } label: {
                                            Image(systemName: "xmark.circle.fill")
                                                .foregroundStyle(Color.errorRed)
                                                .background(Circle().fill(.white))
                                        }
                                        .accessibilityLabel(loc("actions.remove"))
                                        .padding(4)
                                    }
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                        }
                    }

                    if selectedImages.count < maxImages {
                        PhotosPicker(
                            selection: $selectedItems,
                            maxSelectionCount: maxImages - selectedImages.count,
                            matching: .images
                        ) {
                            Label(addImagesLabel, systemImage: "photo.on.rectangle.angled")
                                .font(.subheadline)
                                .foregroundStyle(Color.skyPrimary)
                        }
                        .disabled(selectedImages.count >= maxImages)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                    }

                    Divider()

                    HStack {
                        HStack(spacing: 2) {
                            Text("\(postText.count)")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(postText.count > maxChars ? .red : postText.count > maxChars - 40 ? .orange : .secondary)
                            Text("/ \(maxChars)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        if let errorMessage {
                            Text(errorMessage)
                                .font(.caption)
                                .foregroundStyle(Color.errorRed)
                                .lineLimit(1)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                }
            }
            .background(Color(.systemBackground))
            .pageTitle(loc("compose.reply_title"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(loc("actions.cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isPosting {
                        ProgressView()
                            .scaleEffect(0.8)
                    } else {
                        Button(loc("actions.reply")) {
                            Task { await post() }
                        }
                        .disabled(postText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isPosting)
                    }
                }
            }
        }
        .task {
            await loadParentPost()
        }
        .onChange(of: selectedItems) { _, newItems in
            Task { await handleImageSelection(newItems) }
        }
        .interactiveDismissDisabled(!postText.isEmpty || !selectedImages.isEmpty)
        .sheet(item: $profileToShow) { actor in
            NavigationStack {
                BlueskyProfileView(
                    member: BlueskyListMember(
                        recordURI: "profile:\(actor.did)",
                        actor: actor
                    ),
                    list: nil
                )
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(loc("actions.done")) { profileToShow = nil }
                    }
                }
            }
        }
    }

    /// Shows the parent post author, avatar, and truncated text.
    @ViewBuilder
    private func parentPreview(_ post: RichPost) -> some View {
        let author = post.safeAuthor
        VStack(alignment: .leading, spacing: 4) {
            Button {
                profileToShow = BlueskyActor(
                    did: author.did ?? author.handle ?? "",
                    handle: author.handle ?? "",
                    displayName: author.displayName,
                    avatarURL: author.avatar.flatMap(URL.init)
                )
            } label: {
                HStack(spacing: 6) {
                    if let avatar = author.avatar.flatMap(URL.init) {
                        AsyncImage(url: avatar) { image in
                            image.resizable().scaledToFill()
                        } placeholder: {
                            Circle().fill(Color.skyPrimary.opacity(0.16))
                        }
                        .frame(width: 24, height: 24)
                        .clipShape(Circle())
                    }
                    Text(author.displayName ?? author.handle ?? "")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.primary)
                    if let handle = author.handle {
                        Text("@\(handle)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
            }
            .buttonStyle(.plain)
            if let text = post.safeRecord.text, !text.isEmpty {
                PostTextContent(
                    text: text,
                    onOpenProfile: { handle in
                        profileToShow = BlueskyActor(
                            did: handle,
                            handle: handle,
                            displayName: nil,
                            avatarURL: nil
                        )
                    },
                    font: .subheadline,
                    lineLimit: 4,
                    foregroundStyle: .secondary
                )
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.skyPrimary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 4)
    }

    // MARK: - Image Handling

    private func handleImageSelection(_ items: [PhotosPickerItem]) async {
        for item in items {
            guard let data = try? await item.loadTransferable(type: Data.self) else { continue }
            let mime = item.supportedContentTypes.first?.preferredMIMEType ?? "image/jpeg"
            selectedImages.append((data: data, mimeType: mime))
        }
        selectedItems = []
    }

    /// Fetches the parent post from the API to display as context.
    private func loadParentPost() async {
        do {
            let response = try await blueskyClient.fetchPostThread(
                uri: parentURI,
                depth: nil,
                account: account,
                appPassword: appPassword
            )
            let node = response.thread
            parentPost = RichPost(
                uri: node.post.uri ?? parentURI,
                cid: node.post.cid,
                author: node.post.author,
                record: node.post.record,
                embed: node.post.embed,
                viewer: node.post.viewer,
                replyCount: node.post.replyCount,
                repostCount: node.post.repostCount,
                likeCount: node.post.likeCount,
                indexedAt: node.post.indexedAt
            )
        } catch {
            errorMessage = AppError.userMessage(from: error)
        }
    }

    /// Sends the reply via the Bluesky API and dismisses on success.
    private func post() async {
        let text = postText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        isPosting = true
        errorMessage = nil
        do {
            // Upload images first
            var attachments: [PostImageAttachment] = []
            for img in selectedImages {
                let response = try await blueskyClient.uploadBlob(
                    data: img.data,
                    mimeType: img.mimeType,
                    account: account,
                    appPassword: appPassword,
                    progress: nil
                )
                attachments.append(PostImageAttachment(blob: response.blob, alt: ""))
            }

            _ = try await blueskyClient.createPost(
                text: text,
                images: attachments.isEmpty ? nil : attachments,
                video: nil,
                external: nil,
                replyTo: (parentURI: parentURI, parentCID: parentCID, rootURI: rootURI, rootCID: rootCID),
                quote: nil,
                threadGate: nil,
                allowQuoting: true,
                account: account,
                appPassword: appPassword
            )
            onComplete?()
            dismiss()
        } catch {
            errorMessage = AppError.userMessage(from: error)
            AppLogger.moderation.error("Reply failed: \(error.localizedDescription, privacy: .private)")
        }
        isPosting = false
    }
}
