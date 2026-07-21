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
    /// The hydrated record that caused this notification (e.g. the like record).
    let record: NotificationRecordValue?
    var isRead: Bool
    let indexedAt: String

    var id: String {
        uri
    }

    /// Whether this notification's reasonSubject points to a repost record.
    var isRepostSubject: Bool {
        // Check reasonSubject first
        if let subject = reasonSubject, subject.contains("app.bsky.feed.repost") {
            return true
        }
        // Fallback: check the embedded like record's subject URI
        if let record, record.subjectUri?.contains("app.bsky.feed.repost") == true {
            return true
        }
        return false
    }
}

/// A generic record value embedded in a notification (like, repost, follow, etc.).
struct NotificationRecordValue: Decodable {
    let subjectUri: String?

    enum CodingKeys: String, CodingKey {
        case subject
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // subject can be a string (AT URI) or a { uri: String, cid: String } object
        if let subjectString = try? container.decode(String.self, forKey: .subject) {
            subjectUri = subjectString
        } else if let subjectObj = try? container.decode(SubjectObj.self, forKey: .subject) {
            subjectUri = subjectObj.uri
        } else {
            subjectUri = nil
        }
    }

    private struct SubjectObj: Decodable {
        let uri: String
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
