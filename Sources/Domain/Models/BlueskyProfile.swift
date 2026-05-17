import Foundation

struct BlueskyProfile: Identifiable, Hashable, Codable {
    let id: String
    let did: String
    let handle: String
    let displayName: String?
    let description: String?
    let websiteURL: URL?
    let avatarURL: URL?
    let bannerURL: URL?
    let followersCount: Int?
    let followsCount: Int?
    let postsCount: Int?
    let listsCount: Int?
    let starterPacksCount: Int?
    let createdAt: Date?
    let labels: [String]
    let viewerState: BlueskyViewerState?

    var title: String {
        if let displayName, !displayName.isEmpty {
            return displayName
        }

        return handle
    }

    var profileURL: URL? {
        URL(string: "https://bsky.app/profile/\(handle)")
    }
}

struct BlueskyViewerState: Hashable, Codable {
    let muted: Bool
    let blockedBy: Bool
    let isBlocking: Bool
    let blockingRecordURI: String?
    let isFollowing: Bool
    let followingRecordURI: String?
    let followsYou: Bool
    let mutedByListName: String?
    let blockingByListName: String?
}
