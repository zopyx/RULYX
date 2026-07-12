import Foundation

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

/// Viewer-specific state for a post (like/repost/blocked/muted status).
struct PostViewerState: Decodable {
    let like: String?
    let repost: String?
    let blockedBy: Bool?

    init(like: String? = nil, repost: String? = nil, blockedBy: Bool? = nil) {
        self.like = like
        self.repost = repost
        self.blockedBy = blockedBy
    }
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
