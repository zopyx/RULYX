import SwiftUI

struct NotificationRow: View {
    let notification: NotificationItem
    let relatedPost: RichPost?
    let onAuthorTap: () -> Void
    @EnvironmentObject private var localizationManager: LocalizationManager

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

    private var avatarURL: URL? {
        URL(string: notification.author.avatar ?? "")
    }

    private var initials: String {
        let name = notification.author.displayName ?? notification.author.handle
        return String(name.prefix(1).uppercased())
    }

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

    private var relativeTime: String {
        guard let date = SharedDateFormatters.parseISO8601(notification.indexedAt) else { return "" }
        return relativeTimeString(from: date)
    }

    private func relatedPostCard(_ post: RichPost) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                smallAvatar(for: post.safeAuthor)
                VStack(alignment: .leading, spacing: 1) {
                    Text(post.safeAuthor.displayName ?? post.safeAuthor.handle ?? "")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    if let handle = post.safeAuthor.handle {
                        Text("@\(handle)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer()
                if let createdAt = post.safeRecord.createdAt,
                   let createdDate = parseDate(createdAt)
                {
                    Text(relativeTimeString(from: createdDate))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            if let text = post.safeRecord.text, !text.isEmpty {
                PostTextContent(
                    text: text.replacingOccurrences(of: "\n", with: " "),
                    font: .caption,
                    lineLimit: 4
                )
            }

            if let imageURL = previewImageURL(for: post) {
                ThumbnailImageView(url: imageURL, maxPixelSize: 320) {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.skyPrimary.opacity(0.08))
                }
                .scaledToFill()
                .frame(maxWidth: .infinity)
                .frame(height: 140)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: 10))
            } else if let external = post.embed?.external {
                HStack(spacing: 8) {
                    Image(systemName: "link")
                        .foregroundStyle(.secondary)
                    Text(external.title ?? external.uri ?? "")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
                .background(Color.skyPrimary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
            } else if post.embed?.video != nil {
                HStack(spacing: 8) {
                    Image(systemName: "play.rectangle.fill")
                        .foregroundStyle(Color.skyPrimary)
                    Text(loc: "media.filter.videos")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
                .background(Color.skyPrimary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
            }
        }
        .padding(10)
        .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.primary.opacity(0.05), lineWidth: 1)
        }
    }

    private func smallAvatar(for author: RichAuthor) -> some View {
        Group {
            if let avatarURL = author.avatar.flatMap(URL.init) {
                ThumbnailImageView(url: avatarURL, maxPixelSize: 64) {
                    Circle().fill(Color.skyPrimary.opacity(0.16))
                }
                .scaledToFill()
            } else {
                Circle()
                    .fill(Color.skyPrimary.opacity(0.16))
                    .overlay {
                        Text((author.displayName ?? author.handle ?? "?").prefix(1).uppercased())
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(Color.skyPrimary)
                    }
            }
        }
        .frame(width: 24, height: 24)
        .clipShape(Circle())
    }

    private func previewImageURL(for post: RichPost) -> URL? {
        if let thumb = post.embed?.images?.first?.thumb.flatMap(URL.init) {
            return thumb
        }
        if let fullsize = post.embed?.images?.first?.fullsize.flatMap(URL.init) {
            return fullsize
        }
        return nil
    }
}
