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
    let avatar: String?
    let createdAt: String?
    let viewer: ProfileViewerState?
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

// MARK: - Clearsky

/// Top-level response from the ClearSky blocklist API.
struct ClearskyBlocklistResponse: Decodable {
    let data: ClearskyBlocklistData
}

struct ClearskyBlocklistData: Decodable {
    let blocklist: [ClearskyBlocklistEntry]
}

/// A single entry in a ClearSky blocklist.
struct ClearskyBlocklistEntry: Decodable {
    let did: String
    /// ISO 8601 date string of when the block was created.
    let blockedDate: String

    enum CodingKeys: String, CodingKey {
        case did
        case blockedDate = "blocked_date"
    }
}

// MARK: - Clearsky Lists

/// Response from the ClearSky lists API (`/csky/api/v1/get-list/{handle}`).
struct ClearskyListsResponse: Decodable {
    let data: ClearskyListsData
}

struct ClearskyListsData: Decodable {
    let identifier: String
    let lists: [ClearskyListEntry]
}

/// A moderation list reported by ClearSky.
struct ClearskyListEntry: Decodable, Identifiable {
    let name: String
    let description: String?
    let did: String
    let url: String
    let createdDate: String
    let dateAdded: String

    var id: String {
        url
    }

    enum CodingKeys: String, CodingKey {
        case name, description, did, url
        case createdDate = "created_date"
        case dateAdded = "date_added"
    }
}

/// Response from the ClearSky total count endpoint.
struct ClearskyTotalResponse: Decodable {
    let data: ClearskyTotalData
}

struct ClearskyTotalData: Decodable {
    let count: Int
}

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

// MARK: - Record Creation

/// Request body for creating a list item record with explicit collection and record fields.
struct CreateRecordRequest: Encodable {
    let repo: String
    let collection: String
    let record: ListItemRecord
}

/// Generic request body for creating a record in a specified collection.
/// Used for posts, likes, reposts, follows, blocks, and thread/post gates.
struct CreateGenericRecordRequest<Record: Encodable>: Encodable {
    let repo: String
    let collection: String
    let record: Record
    /// Optional rkey for record creation at a specific key (e.g., threadgate uses the post's rkey).
    let rkey: String?

    init(repo: String, collection: String, record: Record, rkey: String? = nil) {
        self.repo = repo
        self.collection = collection
        self.record = record
        self.rkey = rkey
    }

    enum CodingKeys: String, CodingKey {
        case repo
        case collection
        case record
        case rkey
    }
}

/// Request body for updating a record via `com.atproto.repo.putRecord`.
struct PutRecordRequest: Encodable {
    let repo: String
    let collection: String
    let rkey: String
    let record: ListRecord
}

/// The record value for a list item (member) in a list.
struct ListItemRecord: Encodable {
    let createdAt: String
    let list: String
    let subject: String

    enum CodingKeys: String, CodingKey {
        case createdAt
        case list
        case subject
    }
}

/// The record value for a list definition (`app.bsky.graph.list`).
struct ListRecord: Encodable {
    let type: String
    let purpose: String
    let name: String
    let description: String?
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case type = "$type"
        case purpose
        case name
        case description
        case createdAt
    }
}

/// Generic record for a follow or block relationship (subject-based, no list).
struct SubjectRecord: Encodable {
    let type: String
    let subject: String
    let createdAt: String

    init(type: String, subject: String, createdAt: String = ISO8601DateFormatter().string(from: .now)) {
        self.type = type
        self.subject = subject
        self.createdAt = createdAt
    }

    enum CodingKeys: String, CodingKey {
        case type = "$type"
        case subject
        case createdAt
    }
}

/// Request body for muting/unmuting an actor by DID.
struct ActorReferenceRequest: Encodable {
    let actor: String
}

/// Request body for muting/unmuting an actor list.
struct ListReferenceRequest: Codable {
    let list: String
}

/// Response from `com.atproto.repo.createRecord`.
struct CreateRecordResponse: Decodable {
    let uri: String
    let cid: String
}

/// Response from querying records in a collection.
struct ListRecordsResponse: Decodable {
    let cursor: String?
    let records: [ListRecordEntry]
}

/// A single record entry from `com.atproto.repo.listRecords`.
struct ListRecordEntry: Decodable {
    let uri: String
    let cid: String
    let value: ListItemRecordValue
}

struct ListItemRecordValue: Decodable {
    let createdAt: String
    let list: String
    let subject: String
}

/// Request body for `com.atproto.repo.deleteRecord`.
struct DeleteRecordRequest: Encodable {
    let repo: String
    let collection: String
    let rkey: String
}

/// Placeholder for API calls that return no meaningful body (HTTP 200 with `{}`).
struct EmptyResponse: Decodable {}

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

// MARK: - AT URI Parsing

/// Parsed components of an AT URI (`at://{repo}/{collection}/{rkey}`).
struct ATURIComponents {
    let repo: String
    let collection: String
    let rkey: String
}

/// Parses an AT URI string into its components.
/// Throws `BlueskyAPIError.invalidResponse` if the URI does not match the expected format.
func parseATURI(_ uri: String) throws -> ATURIComponents {
    guard uri.hasPrefix("at://") else {
        throw BlueskyAPIError.invalidResponse
    }

    let value = String(uri.dropFirst(5))
    let segments = value.split(separator: "/")
    guard segments.count >= 3 else {
        throw BlueskyAPIError.invalidResponse
    }

    return ATURIComponents(
        repo: String(segments[0]),
        collection: String(segments[1]),
        rkey: String(segments[2])
    )
}

/// Parses an optional ISO 8601 date string into a `Date`.
func parseDate(_ value: String?) -> Date? {
    guard let value else { return nil }
    return SharedDateFormatters.parseISO8601(value)
}

/// Returns a human-readable relative time string (e.g., "3m ago", "2h ago", "5d ago") or
/// an abbreviated absolute date for items 28+ days old.
@MainActor
func relativeTimeString(from date: Date) -> String {
    let interval = -date.timeIntervalSinceNow
    let minutes = Int(interval / 60)
    let hours = minutes / 60
    let days = hours / 24

    if minutes < 1 { return String.localized("time.just_now") }
    if minutes < 60 {
        let key = minutes == 1 ? "time.minute_ago" : "time.minutes_ago"
        return loc(key).replacingOccurrences(of: "{n}", with: "\(minutes)")
    }
    if hours < 24 {
        let key = hours == 1 ? "time.hour_ago" : "time.hours_ago"
        return loc(key).replacingOccurrences(of: "{n}", with: "\(hours)")
    }
    if days < 28 {
        let key = days == 1 ? "time.day_ago" : "time.days_ago"
        return loc(key).replacingOccurrences(of: "{n}", with: "\(days)")
    }

    return date.formatted(date: .abbreviated, time: .omitted)
}

/// Maps the API's `ProfileViewerState` to the app's domain model `BlueskyViewerState`.
func mapViewerState(_ viewer: ProfileViewerState?) -> BlueskyViewerState? {
    guard let viewer else { return nil }

    return BlueskyViewerState(
        muted: viewer.muted ?? false,
        blockedBy: viewer.blockedBy ?? false,
        isBlocking: viewer.blocking != nil,
        blockingRecordURI: viewer.blocking,
        isFollowing: viewer.following != nil,
        followingRecordURI: viewer.following,
        followsYou: viewer.followedBy != nil,
        mutedByListName: viewer.mutedByList?.name,
        blockingByListName: [viewer.blockingByList?.name].compactMap(\.self)
    )
}

// MARK: - PLC Directory

/// An entry in the PLC directory audit log for a DID.
struct PLCAuditLogEntry: Decodable {
    let did: String
    let operation: PLCOperation
    let cid: String?
    /// Whether this entry has been nullified by a later operation.
    let nullified: Bool?
    let createdAt: String
}

/// An operation recorded in the PLC audit log.
struct PLCOperation: Decodable {
    let type: String?
    /// Handles associated with this operation (e.g., `at://handle.bsky.social`).
    let alsoKnownAs: [String]?
    let services: [String: PLCServiceEntry]?
}

/// A service entry from the PLC directory.
struct PLCServiceEntry: Decodable {
    let type: String?
    let endpoint: String?
}

/// A handle change extracted from the PLC audit log for display in the UI.
struct HandleChange: Identifiable {
    let id: String
    let handle: String
    let date: Date
    let isCurrent: Bool
}

/// Processes a PLC audit log to extract unique handle changes over time.
/// Filters out nullified entries, deduplicates consecutive identical handles,
/// and marks the matching current handle.
func parseHandleChanges(from auditLog: [PLCAuditLogEntry], currentHandle: String) -> [HandleChange] {
    let entries = auditLog
        .filter { !($0.nullified ?? false) }
        .compactMap { entry -> (handle: String, date: Date)? in
            guard let alsoKnownAs = entry.operation.alsoKnownAs,
                  let atHandle = alsoKnownAs.first(where: { $0.hasPrefix("at://") }),
                  let date = parseDate(entry.createdAt)
            else {
                return nil
            }
            let handle = String(atHandle.dropFirst(5))
            return (handle, date)
        }
        .sorted { $0.date < $1.date }

    var seen = Set<String>()
    var result: [HandleChange] = []
    for (handle, date) in entries {
        if seen.insert(handle).inserted {
            result.append(HandleChange(
                id: "\(handle)-\(date.timeIntervalSince1970)",
                handle: handle,
                date: date,
                isCurrent: handle == currentHandle
            ))
        }
    }
    return result
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

// MARK: - Feed / Author Feed (for image download)

/// Response from `app.bsky.feed.getAuthorFeed`.
struct GetAuthorFeedResponse: Decodable {
    let cursor: String?
    let feed: [FeedViewPost]
}

struct FeedViewPost: Decodable {
    let post: PostView
}

struct PostView: Decodable {
    let uri: String
    let embed: EmbedView?
}

struct EmbedView: Decodable {
    let images: [EmbedImageItem]?
}

struct EmbedImageItem: Decodable {
    let fullsize: String
    let alt: String?
}

// MARK: - Rich Feed / Author Feed (for post browser)

/// Response from `app.bsky.feed.getTimeline` / `app.bsky.feed.getFeed` / `app.bsky.feed.getAuthorFeed`.
struct RichFeedResponse: Decodable {
    let cursor: String?
    let feed: [RichFeedEntry]
}

/// A single entry in a rich feed, with optional reply context.
struct RichFeedEntry: Decodable, Identifiable {
    let post: RichPost
    let reply: RichFeedReply?

    var id: String {
        post.uri
    }

    init(post: RichPost, reply: RichFeedReply? = nil) {
        self.post = post
        self.reply = reply
    }

    /// Convenience initializer from a thread node (for composing feed entries from thread data).
    init(threadPost: ThreadPostNode) {
        post = RichPost(
            uri: threadPost.uri ?? "",
            cid: threadPost.cid,
            author: threadPost.author,
            record: threadPost.record,
            embed: threadPost.embed,
            viewer: threadPost.viewer,
            replyCount: threadPost.replyCount,
            repostCount: threadPost.repostCount,
            likeCount: threadPost.likeCount,
            indexedAt: threadPost.indexedAt
        )
        reply = nil
    }
}

/// Reply context for a feed entry (root and parent posts).
struct RichFeedReply: Decodable {
    let root: RichPost?
    let parent: RichPost?
}

/// Viewer-specific state for a post (like/repost status).
struct PostViewerState: Decodable {
    let like: String?
    let repost: String?
}

/// A post with full content and metadata for display in the timeline/feed browser.
struct RichPost: Decodable {
    let uri: String
    let cid: String?
    let author: RichAuthor?
    let record: RichRecord?
    let embed: RichEmbed?
    let viewer: PostViewerState?
    let replyCount: Int?
    let repostCount: Int?
    let likeCount: Int?
    let indexedAt: String?

    /// Returns the author or a fallback with unknown handle.
    var safeAuthor: RichAuthor {
        author ?? RichAuthor(did: "", handle: "unknown", displayName: nil, avatar: nil)
    }

    /// Returns the record or a fallback with empty text.
    var safeRecord: RichRecord {
        record ?? RichRecord(text: "", createdAt: "")
    }

    /// Whether the current viewer has liked this post.
    var isLikedByMe: Bool {
        viewer?.like != nil
    }

    /// Whether the current viewer has reposted this post.
    var isRepostedByMe: Bool {
        viewer?.repost != nil
    }

    /// The AT URI of the viewer's like record, if any.
    var myLikeURI: String? {
        viewer?.like
    }

    /// The AT URI of the viewer's repost record, if any.
    var myRepostURI: String? {
        viewer?.repost
    }
}

/// Author information for a post.
struct RichAuthor: Decodable {
    let did: String?
    let handle: String?
    let displayName: String?
    let avatar: String?
}

/// The record content of a post (text and creation date).
struct RichRecord: Decodable {
    let text: String?
    let createdAt: String?
}

/// Embedded content in a post (images, video, external links, or records with media).
/// Uses a custom decoder to discriminate between embed types by `$type`.
struct RichEmbed: Decodable {
    let images: [RichEmbedImage]?
    let video: RichEmbedVideo?
    let external: RichEmbedExternal?

    enum CodingKeys: String, CodingKey {
        case type = "$type"
        case images
        case thumbnail
        case playlist
        case aspectRatio
        case external
        case media
        case alt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decodeIfPresent(String.self, forKey: .type)
        if type == "app.bsky.embed.images#view" {
            images = try container.decodeIfPresent([RichEmbedImage].self, forKey: .images)
            video = nil
            external = nil
        } else if type == "app.bsky.embed.video#view" {
            images = nil
            video = try RichEmbedVideo(
                thumbnail: container.decodeIfPresent(String.self, forKey: .thumbnail),
                playlist: container.decodeIfPresent(String.self, forKey: .playlist),
                aspectRatio: container.decodeIfPresent(RichAspectRatio.self, forKey: .aspectRatio),
                alt: container.decodeIfPresent(String.self, forKey: .alt)
            )
            external = nil
        } else if type == "app.bsky.embed.external#view" {
            images = nil
            video = nil
            external = try container.decodeIfPresent(RichEmbedExternal.self, forKey: .external)
        } else if type == "app.bsky.embed.recordWithMedia#view" {
            let media = try container.decodeIfPresent(RichEmbed.self, forKey: .media)
            images = media?.images
            video = media?.video
            external = media?.external
        } else {
            images = nil
            video = nil
            external = nil
        }
    }
}

/// An image embedded in a post.
struct RichEmbedImage: Decodable {
    let fullsize: String?
    let thumb: String?
    let alt: String?
}

/// A video embedded in a post.
struct RichEmbedVideo {
    let thumbnail: String?
    let playlist: String?
    let aspectRatio: RichAspectRatio?
    let alt: String?
}

/// An external link embedded in a post (link card).
struct RichEmbedExternal: Decodable {
    let uri: String?
    let title: String?
    let description: String?
    let thumb: String?

    enum CodingKeys: String, CodingKey {
        case uri
        case title
        case description
        case thumb
    }

    /// Custom decoder that handles both string URL and blob object for `thumb`.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        uri = try container.decodeIfPresent(String.self, forKey: .uri)
        title = try container.decodeIfPresent(String.self, forKey: .title)
        description = try container.decodeIfPresent(String.self, forKey: .description)

        // The thumb may be a plain URL string or a blob object with a ref.
        if let thumbURL = try? container.decodeIfPresent(String.self, forKey: .thumb) {
            thumb = thumbURL
        } else if let blob = try container.decodeIfPresent(RichEmbedExternalThumbBlob.self, forKey: .thumb) {
            thumb = blob.urlString
        } else {
            thumb = nil
        }
    }
}

extension RichEmbedExternal {
    /// Whether this external embed is from Tenor (GIF search integration).
    var isTenorEmbed: Bool {
        guard let host = uri.flatMap(URL.init)?.host?.lowercased() else { return false }
        return host == "tenor.com" || host == "www.tenor.com" || host.hasSuffix(".tenor.com")
    }

    /// Returns the preferred URL for inline media display.
    /// For Tenor embeds, prefers animated media assets; otherwise prefers thumb over URI.
    var preferredInlineMediaURL: URL? {
        let thumbURL = thumb.flatMap(URL.init)
        let uriURL = uri.flatMap(URL.init)

        if isTenorEmbed {
            if let thumbURL, thumbURL.isAnimatedMediaAsset {
                return thumbURL
            }
            return uriURL ?? thumbURL
        }

        return thumbURL ?? uriURL
    }
}

private extension URL {
    /// Whether the URL's file extension indicates an animated media format.
    var isAnimatedMediaAsset: Bool {
        let ext = pathExtension.lowercased()
        return ["gif", "webp", "mp4", "webm", "mov", "m4v"].contains(ext)
    }
}

/// Represents a blob object that may appear as a thumb in external embeds.
/// Currently returns `nil` for the URL (unused path).
private struct RichEmbedExternalThumbBlob: Decodable {
    let ref: BlobRef?
    let mimeType: String?
    let size: Int?

    var urlString: String? {
        nil
    }
}

/// Width/height aspect ratio for embedded images and video.
struct RichAspectRatio: Decodable {
    let width: Int?
    let height: Int?
}

// MARK: - Get Posts

/// Response from `app.bsky.feed.getPosts` (batch post lookup).
struct GetPostsResponse: Decodable {
    let posts: [RichPost]
}

// MARK: - Post Thread

/// Response from `app.bsky.feed.getPostThread`.
struct GetPostThreadResponse: Decodable {
    let thread: ThreadNode
}

/// A node in the post thread tree (parent/replies).
final class ThreadNode: Decodable {
    let post: ThreadPostNode
    let parent: ThreadNode?
    let replies: [ThreadNode]?

    init(post: ThreadPostNode, parent: ThreadNode?, replies: [ThreadNode]?) {
        self.post = post
        self.parent = parent
        self.replies = replies
    }
}

/// A post within a thread, with viewer state.
struct ThreadPostNode: Decodable {
    let uri: String?
    let cid: String?
    let author: RichAuthor?
    let record: RichRecord?
    let embed: RichEmbed?
    let viewer: PostViewerState?
    let replyCount: Int?
    let repostCount: Int?
    let likeCount: Int?
    let indexedAt: String?

    var isLikedByMe: Bool {
        viewer?.like != nil
    }

    var isRepostedByMe: Bool {
        viewer?.repost != nil
    }

    var myLikeURI: String? {
        viewer?.like
    }

    var myRepostURI: String? {
        viewer?.repost
    }
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

// MARK: - Blob Upload & Feed Post

/// Response from `com.atproto.repo.uploadBlob`.
struct UploadBlobResponse: Decodable {
    let blob: UploadedBlob
}

/// A blob that has been uploaded to the PDS.
struct UploadedBlob: Decodable {
    let ref: BlobRef
    let mimeType: String
    let size: Int
    let blobType: String?

    enum CodingKeys: String, CodingKey {
        case ref
        case mimeType
        case size
        case blobType = "$type"
    }
}

/// Reference to a blob on the PDS (CID link).
struct BlobRef: Decodable, Encodable {
    let link: String

    enum CodingKeys: String, CodingKey {
        case link = "$link"
    }
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

// MARK: - Reply, Quote, Like, Repost

/// Reply reference pointing to the root and parent of a thread.
struct FeedPostReplyRef: Encodable {
    let root: FeedPostTarget
    let parent: FeedPostTarget
}

/// A target post identified by URI and CID (used for reply roots, likes, reposts).
struct FeedPostTarget: Encodable {
    let uri: String
    let cid: String
}

/// A video attachment being prepared for a post (not yet encoded for the API).
struct FeedPostVideoAttachment {
    let blob: UploadedBlob
    let alt: String
    let aspectRatio: (width: Int, height: Int)?
}

/// A lightweight external link attachment for post creation.
struct FeedPostExternalAttachment {
    let uri: String
    let title: String
    let description: String
}

/// Polymorphic embed type for feed posts: images, record embeds (quotes), video, or external links.
enum FeedPostRecordEmbed: Encodable {
    case images([FeedPostImage])
    case record(uri: String, cid: String)
    case video(FeedPostVideoAttachment)
    case external(FeedPostExternalAttachment)

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .images(images):
            try container.encode("app.bsky.embed.images", forKey: .type)
            try container.encode(images, forKey: .images)
        case let .record(uri, cid):
            try container.encode("app.bsky.embed.record", forKey: .type)
            var record = container.nestedContainer(keyedBy: RecordCodingKeys.self, forKey: .record)
            try record.encode(uri, forKey: .uri)
            try record.encode(cid, forKey: .cid)
        case let .video(attachment):
            try container.encode("app.bsky.embed.video", forKey: .type)
            var video = container.nestedContainer(keyedBy: VideoBlobCodingKeys.self, forKey: .video)
            try video.encode("blob", forKey: .blobType)
            try video.encode(attachment.blob.ref, forKey: .ref)
            try video.encode(attachment.blob.mimeType, forKey: .mimeType)
            try video.encode(attachment.blob.size, forKey: .size)
            try container.encode([String](), forKey: .captions)
            try container.encode(attachment.alt, forKey: .alt)
            if let ratio = attachment.aspectRatio {
                var ar = container.nestedContainer(keyedBy: AspectRatioCodingKeys.self, forKey: .aspectRatio)
                try ar.encode(ratio.width, forKey: .width)
                try ar.encode(ratio.height, forKey: .height)
            }
        case let .external(attachment):
            try container.encode("app.bsky.embed.external", forKey: .type)
            var external = container.nestedContainer(keyedBy: ExternalCodingKeys.self, forKey: .external)
            try external.encode(attachment.uri, forKey: .uri)
            try external.encode(attachment.title, forKey: .title)
            try external.encode(attachment.description, forKey: .description)
        }
    }

    private enum CodingKeys: String, CodingKey {
        case type = "$type"
        case images
        case record
        case video
        case captions
        case alt
        case aspectRatio
        case external
    }

    private enum RecordCodingKeys: String, CodingKey {
        case uri
        case cid
    }

    private enum VideoBlobCodingKeys: String, CodingKey {
        case blobType = "$type"
        case ref
        case mimeType
        case size
    }

    private enum ExternalCodingKeys: String, CodingKey {
        case uri
        case title
        case description
    }

    private enum AspectRatioCodingKeys: String, CodingKey {
        case width
        case height
    }
}

/// Record for creating a like (`app.bsky.feed.like`).
struct LikeRecord: Encodable {
    let subject: FeedPostTarget
    let createdAt: String
}

/// Record for creating a repost (`app.bsky.feed.repost`).
struct RepostRecord: Encodable {
    let subject: FeedPostTarget
    let createdAt: String
}

// MARK: - Moderation Report

/// Request body for `com.atproto.moderation.createReport`.
struct CreateModerationReportRequest: Encodable {
    let reasonType: String
    let reason: String?
    let subject: ModerationReportSubject
    /// Optional tool metadata identifying the reporting client.
    let modTool: ModerationReportTool?
}

/// The subject of a moderation report — either a repo (by DID) or a record (by URI + CID).
struct ModerationReportSubject: Encodable {
    let did: String?
    let uri: String?
    let cid: String?

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        if let did, uri == nil {
            // Report a repo (actor) — use repoRef.
            try container.encode("com.atproto.admin.defs#repoRef", forKey: .type)
            try container.encode(did, forKey: .did)
        } else {
            // Report a specific record — use strongRef.
            try container.encode("com.atproto.repo.strongRef", forKey: .type)
            try container.encode(uri, forKey: .uri)
            try container.encode(cid, forKey: .cid)
        }
    }

    private enum CodingKeys: String, CodingKey {
        case type = "$type"
        case did
        case uri
        case cid
    }
}

/// Metadata about the tool used to submit a moderation report.
struct ModerationReportTool: Encodable {
    /// Name of the reporting tool (e.g., "RULYX/1.0").
    let name: String
    /// Optional key-value metadata associated with the report.
    let meta: [String: String]?
}

/// Response from `com.atproto.moderation.createReport`.
struct CreateModerationReportResponse: Decodable {
    let id: Int
    let reasonType: String
    let reason: String?
    let reportedBy: String
    let createdAt: String
}

/// Predefined reason types for moderation reports, matching AT Protocol lexicon.
enum ModerationReportReasonType: String, CaseIterable, Identifiable {
    case harassmentTargeted = "tools.ozone.report.defs#reasonHarassmentTargeted"
    case harassmentHateSpeech = "tools.ozone.report.defs#reasonHarassmentHateSpeech"
    case harassmentDoxxing = "tools.ozone.report.defs#reasonHarassmentDoxxing"
    case harassmentTroll = "tools.ozone.report.defs#reasonHarassmentTroll"
    case harassmentOther = "tools.ozone.report.defs#reasonHarassmentOther"

    var id: String {
        rawValue
    }

    /// The default reason used when no specific reason is chosen.
    static let simplifiedDefault = ModerationReportReasonType.harassmentOther
}

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

// MARK: - Thread Gate & Post Gate

/// Record for `app.bsky.feed.threadgate` — controls who can reply to a thread.
struct ThreadGateRecord: Encodable {
    let type = "app.bsky.feed.threadgate"
    let post: String
    let allow: [ThreadGateRule]
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case type = "$type"
        case post
        case allow
        case createdAt
    }
}

/// A rule controlling who can reply to a post.
/// - `noReply`: No one can reply.
/// - `mentionRule`: Only mentioned actors can reply.
/// - `followingRule`: Only followed actors can reply.
/// - `listRule`: Only members of a specific list can reply.
enum ThreadGateRule: Encodable, Equatable {
    case noReply
    case mentionRule
    case followingRule
    case listRule(list: String)

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .noReply:
            // An empty `allow` array signals that no one can reply.
            break
        case .mentionRule:
            try container.encode("app.bsky.feed.threadgate#mentionRule", forKey: .type)
        case .followingRule:
            try container.encode("app.bsky.feed.threadgate#followingRule", forKey: .type)
        case let .listRule(list):
            try container.encode("app.bsky.feed.threadgate#listRule", forKey: .type)
            try container.encode(list, forKey: .list)
        }
    }

    private enum CodingKeys: String, CodingKey {
        case type = "$type"
        case list
    }
}

/// Record for `app.bsky.feed.postgate` — controls quote-gating and embedding.
struct PostGateRecord: Encodable {
    let type = "app.bsky.feed.postgate"
    let post: String
    let embeddingRules: [PostGateEmbeddingRule]
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case type = "$type"
        case post
        case embeddingRules
        case createdAt
    }
}

/// A rule controlling whether a post can be embedded (quoted).
/// Currently only supports `disableRule` (no embedding allowed).
enum PostGateEmbeddingRule: Encodable {
    case disableRule

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode("app.bsky.feed.postgate#disableRule", forKey: .type)
    }

    private enum CodingKeys: String, CodingKey {
        case type = "$type"
    }
}
