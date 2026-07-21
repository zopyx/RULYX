import SwiftUI

// MARK: - PostRowView

/// Composable post row with configurable display style (full, compact, minimal, threadReply, card),
/// embedding author header, reply context, text content, media, and action bar.
struct PostRowView: View {
    let entry: RichFeedEntry
    let style: PostDisplayStyle
    let callbacks: PostRowCallbacks
    var avatarSize: CGFloat
    @Environment(\.colorScheme) private var colorScheme

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

    // MARK: - Standard Layout (Twitter/X-style)

    /// Twitter/X-style layout: avatar on the left, content column on the right.
    /// The space below the avatar stays empty.
    private var standardContent: some View {
        HStack(alignment: .top, spacing: 8) {
            // Left column: avatar only
            avatarButton

            // Right column: display name, handle, time, and post content
            VStack(alignment: .leading, spacing: 4) {
                // Row 1: display name, handle, relative time
                authorNameRow

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
                    font: .callout,
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

    // MARK: - Avatar Button

    /// The author avatar as a standalone tappable button.
    private var avatarButton: some View {
        Button {
            callbacks.onOpenProfile?(author.handle ?? author.did ?? "")
        } label: {
            if let url = author.avatar.flatMap(URL.init) {
                ThumbnailImageView(url: url, maxPixelSize: 72) {
                    Circle().fill(Color.skyPrimary.opacity(0.16))
                }
                .scaledToFill()
                .frame(width: avatarSize, height: avatarSize)
                .clipShape(Circle())
            } else {
                Circle()
                    .fill(Color.skyPrimary.opacity(0.16))
                    .frame(width: avatarSize, height: avatarSize)
                    .overlay {
                        Text(displayName.prefix(1).uppercased())
                            .font(.caption.weight(.bold))
                            .foregroundStyle(Color.skyPrimary)
                    }
            }
        }
        .buttonStyle(.plain)
    }

    /// The display name falling back to the handle if unavailable.
    private var displayName: String {
        author.displayName ?? author.handle ?? ""
    }

    /// Whether to show the display name separately from the handle.
    private var shouldShowDisplayName: Bool {
        guard let rawDisplayName = author.displayName,
              let rawHandle = author.handle
        else { return false }
        return rawDisplayName != rawHandle
    }

    // MARK: - Author Name Row

    /// First row: display name, handle, and relative timestamp — tappable to open profile.
    private var authorNameRow: some View {
        Button {
            callbacks.onOpenProfile?(author.handle ?? author.did ?? "")
        } label: {
            HStack(spacing: 4) {
                if shouldShowDisplayName {
                    Text(displayName)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                        .foregroundStyle(.primary)
                }
                if let handle = author.handle {
                    Text("@\(handle)")
                        .font(.caption)
                        .foregroundStyle(colorScheme == .dark ? Color(white: 0.73) : .secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                if let created = post.safeRecord.createdAt, let date = parseDate(created) {
                    Text(relativeTimeString(from: date))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .buttonStyle(.plain)
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
