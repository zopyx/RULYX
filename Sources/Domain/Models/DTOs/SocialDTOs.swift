import Foundation

// MARK: - Followers / Following

/// Response from `app.bsky.graph.getFollowers`.
struct GetFollowersResponse: Decodable {
    let cursor: String?
    let followers: [ActorView]
}

/// Response from `app.bsky.graph.getFollows`.
struct GetFollowsResponse: Decodable {
    let cursor: String?
    let follows: [ActorView]
}

/// Response from `app.bsky.actor.searchActorsTypeahead`.
struct SearchActorsResponse: Decodable {
    let cursor: String?
    let actors: [ActorView]
}

// MARK: - Likes

/// Response from `app.bsky.feed.getLikes`.
struct GetLikesResponse: Decodable {
    let cursor: String?
    let likes: [LikeItem]
}

/// A single like entry with actor and timestamp.
struct LikeItem: Decodable {
    let createdAt: String
    let actor: RichAuthor
}
