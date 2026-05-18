import SwiftUI

struct NotificationRow: View {
    let notification: NotificationItem

    var body: some View {
        HStack(spacing: 12) {
            iconCircle
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .top, spacing: 6) {
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
                        }
                        if !notification.isRead {
                            Circle()
                                .fill(Color.skyPrimary)
                                .frame(width: 8, height: 8)
                        }
                    }
                }
                Text(relativeTime)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 4)
        .opacity(notification.isRead ? 0.7 : 1)
    }

    private var iconCircle: some View {
        ZStack {
            Circle()
                .fill(iconColor.opacity(0.15))
                .frame(width: 36, height: 36)
            Image(systemName: iconName)
                .font(.caption.weight(.semibold))
                .foregroundStyle(iconColor)
        }
    }

    private var iconName: String {
        switch notification.reason {
        case "like": "heart.fill"
        case "repost": "arrow.trianglehead.2.counterclockwise"
        case "follow": "person.fill"
        case "reply": "arrowshape.turn.up.left.fill"
        case "quote": "quote.bubble.fill"
        case "mention": "at"
        case "starterpack_joined": "square.and.arrow.down.fill"
        default: "bell.fill"
        }
    }

    private var iconColor: Color {
        switch notification.reason {
        case "like": .red
        case "repost": .green
        case "follow": .blue
        case "reply": Color.skyPrimary
        case "quote": .purple
        case "mention": .orange
        case "starterpack_joined": .teal
        default: .secondary
        }
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
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let date = formatter.date(from: notification.indexedAt) ?? {
            formatter.formatOptions = [.withInternetDateTime]
            return formatter.date(from: notification.indexedAt)
        }() else { return "" }
        return relativeTimeString(from: date)
    }
}
