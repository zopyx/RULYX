import Foundation

struct PushNotificationRoute {
    let conversationID: String?
    let memberDID: String?

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
