import Foundation

/// Represents a Bluesky moderation list that the user has subscribed to.
/// Tracks the list metadata along with the subscription timestamp.
struct SubscribedListInfo: Identifiable {
    // MARK: - Properties

    /// The AT URI of the subscribed list.
    let id: String
    /// The full AT URI of the list record (may differ from `id` in format).
    let listURI: String
    /// The display name of the subscribed list.
    let name: String
    /// The description of the subscribed list, if available.
    let description: String?
    /// The DID of the list owner/creator.
    let ownerDID: String
    /// The handle of the list owner.
    let ownerHandle: String
    /// The display name of the list owner, if available.
    let ownerDisplayName: String?
    /// The number of members in this list, if available.
    let memberCount: Int?
    /// The kind of list (moderation, internal, regular).
    let kind: BlueskyList.Kind
    /// The date the user subscribed to this list, if known.
    let subscribedAt: Date?
}
