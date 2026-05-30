import SwiftUI

// MARK: - PostRowView

/// Composable post row with configurable display style (full, compact, minimal, threadReply, card),
/// embedding author header, reply context, text content, media, and action bar.
struct PostRowView: View {
    let entry: RichFeedEntry
    let style: PostDisplayStyle
    let callbacks: PostRowCallbacks
    var avatarSize: CGFloat

    init(entry: RichFeedEntry, style: PostDisplayStyle = .full, callbacks: PostRowCallbacks = PostRowCallbacks(), avatarSize: CGFloat? = nil) {
        self.entry = entry
        self.style = style
        self.callbacks = callbacks
        self.avatarSize = avatarSize ?? style.defaultAvatarSize
    }

    private var post: RichPost {
        entry.post
    }

    private var author: RichAuthor {
        post.safeAuthor
    }

    var body: some View {
        if style == .card {
            cardContent
        } else {
            standardContent
        }
    }

    // MARK: - Standard Layout

    private var standardContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            PostAuthorHeader(
                author: author,
                createdAt: post.safeRecord.createdAt,
                onOpenProfile: callbacks.onOpenProfile,
                avatarSize: avatarSize
            )

            if style != .minimal, style != .threadReply, let parent = entry.reply?.parent {
                PostReplyContextView(parent: parent)
            }

            if let text = post.safeRecord.text, !text.isEmpty {
                PostTextContent(
                    text: text,
                    onTapThread: callbacks.onTapThread,
                    onOpenProfile: callbacks.onOpenProfile,
                    onOpenURL: callbacks.onOpenURL,
                    font: style == .threadReply ? .subheadline : .body,
                    lineLimit: style == .threadReply ? 10 : nil
                )
            }

            if style != .minimal, let embed = post.embed {
                PostEmbedView(
                    embed: embed,
                    onTapImage: callbacks.onTapImage,
                    onPlayVideo: callbacks.onPlayVideo
                )
            }

            if style == .full || style == .compact || style == .threadReply {
                PostActionBar(
                    replyCount: post.replyCount,
                    repostCount: post.repostCount,
                    likeCount: post.likeCount,
                    isLiked: callbacks.isLiked,
                    isReposted: callbacks.isReposted,
                    callbacks: callbacks
                )
            }
        }
    }

    // MARK: - Card Layout

    private var cardContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            PostAuthorHeader(
                author: author,
                createdAt: post.safeRecord.createdAt,
                onOpenProfile: callbacks.onOpenProfile,
                avatarSize: avatarSize
            )

            if let text = post.safeRecord.text, !text.isEmpty {
                PostTextContent(
                    text: text,
                    onTapThread: callbacks.onTapThread,
                    onOpenProfile: callbacks.onOpenProfile,
                    onOpenURL: callbacks.onOpenURL,
                    font: .caption,
                    lineLimit: 4
                )
            }

            if let embed = post.embed {
                PostEmbedView(
                    embed: embed,
                    onTapImage: callbacks.onTapImage,
                    onPlayVideo: callbacks.onPlayVideo
                )
            }
        }
        .padding(10)
        .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.primary.opacity(0.05), lineWidth: 1)
        }
    }
}

extension PostDisplayStyle {
    var defaultAvatarSize: CGFloat {
        switch self {
        case .full, .compact, .minimal: 36
        case .threadReply: 28
        case .card: 24
        }
    }
}
