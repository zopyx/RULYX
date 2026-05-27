import Foundation

/// Represents a Bluesky user profile fetched from the AT Protocol.
/// Contains profile metadata, social statistics, and viewer state.
struct BlueskyProfile: Identifiable, Hashable, Codable {
    // MARK: - Properties

    /// The profile's AT URI (e.g., `at://did:plc:.../app.bsky.actor.profile/self`).
    let id: String
    /// The decentralized identifier (DID) for this profile.
    let did: String
    /// The user's handle (e.g., `alice.bsky.social`).
    let handle: String
    /// The user's display name, if set.
    let displayName: String?
    /// The user's profile description/bio, if set.
    let description: String?
    /// The URL to the user's website, if provided.
    let websiteURL: URL?
    /// The URL to the user's avatar image.
    let avatarURL: URL?
    /// The URL to the user's banner image.
    let bannerURL: URL?
    /// The number of followers this profile has.
    let followersCount: Int?
    /// The number of accounts this profile follows.
    let followsCount: Int?
    /// The number of posts this profile has made.
    let postsCount: Int?
    /// The number of lists this profile owns.
    let listsCount: Int?
    /// The number of starter packs this profile owns.
    let starterPacksCount: Int?
    /// The date this profile was created on Bluesky.
    let createdAt: Date?
    /// Labels applied to this profile (self-labels or moderation labels).
    let labels: [String]
    /// The viewer's relationship to this profile (blocking, muting, following, etc.).
    let viewerState: BlueskyViewerState?

    // MARK: - Computed Properties

    /// Returns the display name if available and non-empty; falls back to the handle.
    var title: String {
        if let displayName, !displayName.isEmpty {
            return displayName
        }

        return handle
    }

    /// Constructs the bsky.app profile URL for this user.
    var profileURL: URL? {
        URL(string: "https://bsky.app/profile/\(handle)")
    }
}

/// Represents the authenticated viewer's relationship with a profile.
/// Provides blocking, muting, and following state from the viewer's perspective.
struct BlueskyViewerState: Hashable, Codable {
    // MARK: - Properties

    /// Whether the viewer has muted this profile.
    let muted: Bool
    /// Whether the viewer is blocked by this profile.
    let blockedBy: Bool
    /// Whether the viewer is blocking this profile.
    let isBlocking: Bool
    /// The AT URI of the blocking record, if the viewer is blocking.
    let blockingRecordURI: String?
    /// Whether the viewer is following this profile.
    let isFollowing: Bool
    /// The AT URI of the follow record, if the viewer is following.
    let followingRecordURI: String?
    /// Whether the profile follows the viewer back.
    let followsYou: Bool
    /// The name of the list that muted this profile, if muted via a list.
    let mutedByListName: String?
    /// The names of lists that are blocking this profile.
    let blockingByListName: [String]
}
