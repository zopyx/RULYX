import SwiftUI

// MARK: - NotificationRow

/// A single notification row — shows the author avatar, reason text
/// (liked/reposted/followed/etc.), relative timestamp, read/unread indicator,
/// and an inline card for the related post (if available).
struct NotificationRow: View {
    let notification: NotificationItem
    let relatedPost: RichPost?
    let onAuthorTap: () -> Void
    @EnvironmentObject private var localizationManager: LocalizationManager

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .center, spacing: 6) {
                avatarView
                    .frame(width: 32, height: 32)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text(notification.author.displayName ?? notification.author.handle)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                        Text(reasonText)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        if !notification.isRead {
                            Circle()
                                .fill(Color.skyPrimary)
                                .frame(width: 8, height: 8)
                        }
                    }
                    Text(relativeTime)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture(perform: onAuthorTap)

            if let relatedPost {
                relatedPostCard(relatedPost)
                    .padding(.leading, 38)
            }
        }
        .padding(.vertical, 4)
        .opacity(notification.isRead ? 0.7 : 1)
    }

    /// Author avatar with initials fallback and border overlay.
    private var avatarView: some View {
        AsyncImage(url: avatarURL) { image in
            image
                .resizable()
                .scaledToFill()
        } placeholder: {
            Circle()
                .fill(Color.skyPrimary.opacity(0.16))
                .overlay {
                    Text(initials)
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(Color.skyPrimary)
                }
        }
        .frame(width: 32, height: 32)
        .clipShape(Circle())
        .overlay {
            Circle()
                .stroke(Color.white.opacity(0.15), lineWidth: 1)
        }
    }

    /// Resolves the author's avatar URL string.
    private var avatarURL: URL? {
        URL(string: notification.author.avatar ?? "")
    }

    /// Single-character initial from display name or handle.
    private var initials: String {
        let name = notification.author.displayName ?? notification.author.handle
        return String(name.prefix(1).uppercased())
    }

    /// Localized reason text based on the notification reason string.
    private var reasonText: String {
        switch notification.reason {
        case "like": loc("notifications.reason.like")
        case "repost": loc("notifications.reason.repost")
        case "follow": loc("notifications.reason.follow")
        case "reply": loc("notifications.reason.reply")
        case "quote": loc("notifications.reason.quote")
        case "mention": loc("notifications.reason.mention")
        case "starterpack_joined": loc("notifications.reason.starterpack_joined")
        default: ""
        }
    }

    /// Relative time string from the notification's indexedAt date.
    private var relativeTime: String {
        guard let date = SharedDateFormatters.parseISO8601(notification.indexedAt) else { return "" }
        return relativeTimeString(from: date)
    }

    /// Inline preview card for the post associated with this notification.
    private func relatedPostCard(_ post: RichPost) -> some View {
        PostRowView(
            entry: RichFeedEntry(post: post),
            style: .card,
            callbacks: PostRowCallbacks(
                onTapImage: nil,
                onPlayVideo: nil
            )
        )
    }
}
