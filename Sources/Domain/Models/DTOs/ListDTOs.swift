import Foundation

// MARK: - Lists

/// Response from `app.bsky.graph.getLists`.
struct GetListsResponse: Decodable {
    let lists: [ListView]
}

/// Paginated response from `app.bsky.graph.getListMutes`.
struct PagedListsResponse: Decodable {
    let cursor: String?
    let lists: [ListView]
}

/// Response from `app.bsky.graph.getListsWithMembership`.
struct ListsWithMembershipResponse: Decodable {
    let listsWithMembership: [ListWithMembership]
}

/// Response from `app.bsky.graph.getStarterPacksWithMembership`.
struct StarterPacksWithMembershipResponse: Decodable {
    let starterPacksWithMembership: [StarterPackWithMembership]
}

/// Response from `app.bsky.graph.getList`.
struct GetListResponse: Decodable {
    let cursor: String?
    let list: ListView?
    let items: [ListItemView]
}

/// A list as returned by the Bluesky API (full detail).
struct ListView: Decodable {
    let uri: String
    let cid: String?
    let creator: ActorView?
    let name: String
    let description: String?
    let purpose: ListPurpose
    let listItemCount: Int?
    let avatar: String?
    let viewer: ListViewerState?
    let indexedAt: String?
}

/// A list as returned by the Bluesky API (basic view, without creator).
struct ListViewBasic: Decodable {
    let uri: String
    let cid: String?
    let name: String
    let purpose: ListPurpose
    let listItemCount: Int?
    let avatar: String?
    let viewer: ListViewerState?
    let indexedAt: String?
}

/// Viewer-specific state for a list (muted/blocked status).
struct ListViewerState: Decodable {
    let muted: Bool?
    let blocked: String?
}

/// A list with the current user's membership item attached.
struct ListWithMembership: Decodable {
    let list: ListViewBasic
    let listItem: ListItemView?
}

/// An item (member) in a list.
struct ListItemView: Decodable {
    let uri: String
    let subject: ActorView
    let createdAt: String?
}

/// A starter pack with the current user's membership item attached.
struct StarterPackWithMembership: Decodable {
    let starterPack: StarterPackViewBasic
    let listItem: ListItemView?
}

/// A starter pack in its basic view.
struct StarterPackViewBasic: Decodable {
    let uri: String
    let name: String?
    let listItemCount: Int?
    let joinedAllTimeCount: Int?
}

/// An actor/viewer returned by the API (profile summary).
struct ActorView: Decodable {
    let did: String
    let handle: String
    let displayName: String?
    let description: String?
    let avatar: String?
    let createdAt: String?
    let viewer: ProfileViewerState?

    init(
        did: String,
        handle: String,
        displayName: String?,
        description: String? = nil,
        avatar: String?,
        createdAt: String?,
        viewer: ProfileViewerState?
    ) {
        self.did = did
        self.handle = handle
        self.displayName = displayName
        self.description = description
        self.avatar = avatar
        self.createdAt = createdAt
        self.viewer = viewer
    }
}

/// Response from `app.bsky.graph.getBlocks`.
struct GetBlocksResponse: Decodable {
    let cursor: String?
    let blocks: [ActorView]
}

/// Response from `app.bsky.actor.getProfiles` (batch profile lookup).
struct GetProfilesResponse: Decodable {
    let profiles: [ProfileViewDetailed]
}

// MARK: - List Purpose

/// The purpose type of a Bluesky list (curation or moderation).
enum ListPurpose: String, Decodable {
    case curate = "app.bsky.graph.defs#curatelist"
    case mod = "app.bsky.graph.defs#modlist"

    var kind: BlueskyList.Kind {
        switch self {
        case .curate:
            .regular
        case .mod:
            .moderation
        }
    }

    var displayTitle: String {
        switch self {
        case .curate:
            "Curation list"
        case .mod:
            "Moderation list"
        }
    }
}
