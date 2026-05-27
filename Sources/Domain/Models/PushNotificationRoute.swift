import Foundation

/// Parses and extracts routing information from push notification payloads.
/// Determines whether the notification should navigate to a conversation or profile view.
struct PushNotificationRoute {
    // MARK: - Properties

    /// The conversation ID extracted from the notification payload, if present.
    let conversationID: String?
    /// The actor DID extracted from the notification payload, if present.
    let memberDID: String?

    // MARK: - Init

    /// Attempts to parse navigation routing info from a push notification's `userInfo` dictionary.
    /// Checks multiple possible key names within the top-level, `chat`, and `data` sub-dictionaries.
    /// Returns nil if neither a conversationID nor a memberDID can be found.
    /// - Parameter userInfo: The notification payload dictionary (as received from `UNNotification.request.content.userInfo`).
    init?(userInfo: [AnyHashable: Any]) {
        conversationID = PushNotificationRoute.stringValue(
            forAnyOf: ["convoId", "conversationId", "chatConvoId"],
            in: userInfo
        ) ?? PushNotificationRoute.stringValue(
            forAnyOf: ["convoId", "conversationId", "chatConvoId"],
            in: userInfo["chat"] as? [AnyHashable: Any]
        ) ?? PushNotificationRoute.stringValue(
            forAnyOf: ["convoId", "conversationId", "chatConvoId"],
            in: userInfo["data"] as? [AnyHashable: Any]
        )

        memberDID = PushNotificationRoute.stringValue(
            forAnyOf: ["did", "memberDid", "actorDid", "senderDid"],
            in: userInfo
        ) ?? PushNotificationRoute.stringValue(
            forAnyOf: ["did", "memberDid", "actorDid", "senderDid"],
            in: userInfo["chat"] as? [AnyHashable: Any]
        ) ?? PushNotificationRoute.stringValue(
            forAnyOf: ["did", "memberDid", "actorDid", "senderDid"],
            in: userInfo["data"] as? [AnyHashable: Any]
        )

        if conversationID == nil, memberDID == nil {
            return nil
        }
    }

    // MARK: - Private Helpers

    /// Attempts to find a non-empty string value for any of the provided keys in the dictionary.
    /// - Parameters:
    ///   - keys: An ordered list of key names to check.
    ///   - dictionary: The dictionary to search (may be nil).
    /// - Returns: The first non-empty string found, or nil.
    private static func stringValue(
        forAnyOf keys: [String],
        in dictionary: [AnyHashable: Any]?
    ) -> String? {
        guard let dictionary else { return nil }
        for key in keys {
            if let value = dictionary[key] as? String, !value.isEmpty {
                return value
            }
        }
        return nil
    }
}
