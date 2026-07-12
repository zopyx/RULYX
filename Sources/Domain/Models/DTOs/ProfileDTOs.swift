import Foundation

// MARK: - Profile

/// Detailed profile view from `app.bsky.actor.getProfile`.
struct ProfileViewDetailed: Decodable {
    let did: String
    let handle: String
    let displayName: String?
    let description: String?
    let website: String?
    let avatar: String?
    let banner: String?
    let followersCount: Int?
    let followsCount: Int?
    let postsCount: Int?
    let associated: ProfileAssociated?
    let createdAt: String?
    let labels: [ProfileLabel]?
    let viewer: ProfileViewerState?
}

/// Counts associated with a profile (lists, starter packs).
struct ProfileAssociated: Decodable {
    let lists: Int?
    let starterPacks: Int?
}

/// A label applied to a profile.
struct ProfileLabel: Decodable {
    let val: String
}

/// Viewer-specific relationship state for a profile.
struct ProfileViewerState: Decodable {
    /// Whether the viewer has muted this actor.
    let muted: Bool?
    /// Whether the viewer is blocked by this actor.
    let blockedBy: Bool?
    /// Record URI of the block relationship (nil if not blocking).
    let blocking: String?
    /// Record URI of the follow relationship (nil if not following).
    let following: String?
    /// Record URI if this actor follows the viewer (nil otherwise).
    let followedBy: String?
    /// The list through which the viewer has muted this actor (if applicable).
    let mutedByList: ListViewBasic?
    /// The list through which the viewer has blocked this actor (if applicable).
    let blockingByList: ListViewBasic?
}

// MARK: - Profile Record

/// The record value for an actor profile (`app.bsky.actor.profile`).
/// Used with `com.atproto.repo.putRecord` to update display name, description,
/// avatar, and banner.
struct ProfileRecord: Encodable {
    let type = "app.bsky.actor.profile"
    let displayName: String?
    let description: String?
    let avatar: UploadedBlob?
    let banner: UploadedBlob?
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case type = "$type"
        case displayName
        case description
        case avatar
        case banner
        case createdAt
    }
}

/// Decodable version of the profile record value, used when fetching the
/// current profile via `com.atproto.repo.getRecord` so existing blob refs
/// can be preserved during an edit.
struct ProfileRecordValue: Decodable {
    let displayName: String?
    let description: String?
    let avatar: UploadedBlob?
    let banner: UploadedBlob?
    let createdAt: String?

    enum CodingKeys: String, CodingKey {
        case displayName
        case description
        case avatar
        case banner
        case createdAt
    }
}

/// Response wrapper for `com.atproto.repo.getRecord`.
struct GetProfileRecordResponse: Decodable {
    let uri: String
    let cid: String
    let value: ProfileRecordValue
}

/// The full record for a feed post (`app.bsky.feed.post`).
struct FeedPostRecord: Encodable {
    let type = "app.bsky.feed.post"
    let text: String
    let createdAt: String
    let reply: FeedPostReplyRef?
    let embed: FeedPostRecordEmbed?

    enum CodingKeys: String, CodingKey {
        case type = "$type"
        case text
        case createdAt
        case reply
        case embed
    }

    init(text: String, createdAt: String, reply: FeedPostReplyRef? = nil, embed: FeedPostRecordEmbed? = nil) {
        self.text = text
        self.createdAt = createdAt
        self.reply = reply
        self.embed = embed
    }
}

/// An image attachment within a feed post.
struct FeedPostImage: Encodable {
    let image: FeedPostImageRef
    let alt: String
}

/// Reference to an uploaded image blob, including type, ref, mime, and size.
struct FeedPostImageRef: Encodable {
    let type = "blob"
    let ref: BlobRef
    let mimeType: String
    let size: Int

    enum CodingKeys: String, CodingKey {
        case type = "$type"
        case ref
        case mimeType
        case size
    }
}
