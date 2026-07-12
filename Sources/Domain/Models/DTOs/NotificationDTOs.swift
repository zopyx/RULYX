import Foundation

// MARK: - Notifications

/// Response from `app.bsky.notification.listNotifications`.
struct ListNotificationsResponse: Decodable {
    let cursor: String?
    let notifications: [NotificationItem]
}

/// A single notification item.
struct NotificationItem: Decodable, Identifiable {
    let uri: String
    let cid: String
    let author: ActorView
    /// The reason for the notification (e.g., "like", "repost", "follow", "mention").
    let reason: String
    /// The AT URI of the subject (post or record) that triggered the notification.
    let reasonSubject: String?
    var isRead: Bool
    let indexedAt: String

    var id: String {
        uri
    }
}

/// Request body for `app.bsky.notification.updateSeen`.
struct UpdateSeenRequest: Encodable {
    let seenAt: String
}

/// Response from `app.bsky.notification.getUnreadCount`.
struct UnreadCountResponse: Decodable {
    let count: Int
}
