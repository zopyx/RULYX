import SwiftUI

struct ReplyComposerView: View {
    let account: AppAccount
    let appPassword: String
    let blueskyClient: LiveBlueskyClient
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

    private let maxChars = 300

    var body: some View {
        NavigationStack {
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
                            Text(loc("post.placeholder"))
                                .font(.body)
                                .foregroundStyle(.tertiary)
                                .padding(.horizontal, 20)
                                .padding(.vertical, 14)
                                .allowsHitTesting(false)
                        }
                    }

                Divider()

                HStack {
                    HStack(spacing: 2) {
                        Text("\(postText.count)")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(postText.count > maxChars ? .red : postText.count > maxChars - 40 ? .orange : .secondary)
                        Text("/ \(maxChars)")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }

                    Spacer()

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .lineLimit(1)
                    }

                    Button(loc("actions.reply")) {
                        Task { await post() }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(postText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isPosting)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
            .navigationTitle(loc("post.reply"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(loc("actions.cancel")) { dismiss() }
                }
            }
        }
        .task {
            await loadParentPost()
        }
        .interactiveDismissDisabled(!postText.isEmpty)
    }

    @ViewBuilder
    private func parentPreview(_ post: RichPost) -> some View {
        let author = post.safeAuthor
        VStack(alignment: .leading, spacing: 4) {
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
                if let handle = author.handle {
                    Text("@\(handle)")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                Spacer()
            }
            if let text = post.safeRecord.text, !text.isEmpty {
                Text(text)
                    .font(.subheadline)
                    .lineLimit(4)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.skyPrimary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 4)
    }

    private func loadParentPost() async {
        do {
            let response = try await blueskyClient.fetchPostThread(uri: parentURI, account: account, appPassword: appPassword)
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

    private func post() async {
        let text = postText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        isPosting = true
        errorMessage = nil
        do {
            _ = try await blueskyClient.createPost(
                text: text,
                replyTo: (parentURI: parentURI, parentCID: parentCID, rootURI: rootURI, rootCID: rootCID),
                account: account,
                appPassword: appPassword
            )
            onComplete?()
            dismiss()
        } catch {
            errorMessage = AppError.userMessage(from: error)
            AppLogger.moderation.error("Reply failed: \(error.localizedDescription, privacy: .public)")
        }
        isPosting = false
    }
}
