import Foundation

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

    enum ThreadType: String, Decodable {
        case post = "app.bsky.feed.defs#threadViewPost"
        case blocked = "app.bsky.feed.defs#blockedPost"
        case notFound = "app.bsky.feed.defs#notFoundPost"
    }

    private struct BlockedPostPayload: Decodable {
        let uri: String?
        let blocked: Bool?
        let author: BlockedAuthor?
    }

    private struct BlockedAuthor: Decodable {
        let did: String?
    }

    required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decodeIfPresent(String.self, forKey: .type)

        switch type {
        case ThreadType.blocked.rawValue:
            let payload = try BlockedPostPayload(from: decoder)
            let viewer = PostViewerState(blockedBy: true)
            let author = payload.author.map {
                RichAuthor(did: $0.did, handle: nil, displayName: nil, avatar: nil)
            }
            post = ThreadPostNode(
                uri: payload.uri,
                cid: nil,
                author: author,
                record: nil,
                embed: nil,
                viewer: viewer,
                replyCount: nil,
                repostCount: nil,
                likeCount: nil,
                indexedAt: nil,
                isBlocked: true
            )
            parent = nil
            replies = nil

        case ThreadType.notFound.rawValue:
            let uri = try container.decodeIfPresent(String.self, forKey: .uri)
            post = ThreadPostNode(
                uri: uri,
                cid: nil,
                author: nil,
                record: nil,
                embed: nil,
                viewer: nil,
                replyCount: nil,
                repostCount: nil,
                likeCount: nil,
                indexedAt: nil,
                isNotFound: true
            )
            parent = nil
            replies = nil

        default:
            post = try container.decode(ThreadPostNode.self, forKey: .post)
            parent = try container.decodeIfPresent(ThreadNode.self, forKey: .parent)
            replies = try container.decodeIfPresent([ThreadNode].self, forKey: .replies)
        }
    }

    private enum CodingKeys: String, CodingKey {
        case type = "$type"
        case post, parent, replies, uri
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
    let isBlocked: Bool
    let isNotFound: Bool

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

    init(
        uri: String? = nil,
        cid: String? = nil,
        author: RichAuthor? = nil,
        record: RichRecord? = nil,
        embed: RichEmbed? = nil,
        viewer: PostViewerState? = nil,
        replyCount: Int? = nil,
        repostCount: Int? = nil,
        likeCount: Int? = nil,
        indexedAt: String? = nil,
        isBlocked: Bool = false,
        isNotFound: Bool = false
    ) {
        self.uri = uri
        self.cid = cid
        self.author = author
        self.record = record
        self.embed = embed
        self.viewer = viewer
        self.replyCount = replyCount
        self.repostCount = repostCount
        self.likeCount = likeCount
        self.indexedAt = indexedAt
        self.isBlocked = isBlocked
        self.isNotFound = isNotFound
    }

    enum CodingKeys: String, CodingKey {
        case uri, cid, author, record, embed, viewer
        case replyCount, repostCount, likeCount, indexedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        uri = try container.decodeIfPresent(String.self, forKey: .uri)
        cid = try container.decodeIfPresent(String.self, forKey: .cid)
        author = try container.decodeIfPresent(RichAuthor.self, forKey: .author)
        record = try container.decodeIfPresent(RichRecord.self, forKey: .record)
        embed = try container.decodeIfPresent(RichEmbed.self, forKey: .embed)
        viewer = try container.decodeIfPresent(PostViewerState.self, forKey: .viewer)
        replyCount = try container.decodeIfPresent(Int.self, forKey: .replyCount)
        repostCount = try container.decodeIfPresent(Int.self, forKey: .repostCount)
        likeCount = try container.decodeIfPresent(Int.self, forKey: .likeCount)
        indexedAt = try container.decodeIfPresent(String.self, forKey: .indexedAt)
        isBlocked = false
        isNotFound = false
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
