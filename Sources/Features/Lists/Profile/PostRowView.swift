import SwiftUI

// MARK: - PostRowView

/// Composable post row with configurable display style (full, compact, minimal),
/// embedding author header, reply context, text content, media, and action bar.
struct PostRowView: View {
    /// The post data to display.
    let entry: RichFeedEntry
    /// How the post should be rendered (full, compact, minimal).
    let style: PostDisplayStyle
    /// Callbacks for user interactions (tap image, play video, open profile, etc.).
    let callbacks: PostRowCallbacks

    init(entry: RichFeedEntry, style: PostDisplayStyle = .full, callbacks: PostRowCallbacks = PostRowCallbacks()) {
        self.entry = entry
        self.style = style
        self.callbacks = callbacks
    }

    /// Convenience accessor for the underlying post.
    private var post: RichPost {
        entry.post
    }

    /// Convenience accessor for the post author.
    private var author: RichAuthor {
        post.safeAuthor
    }

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            PostAuthorHeader(
                author: author,
                createdAt: post.safeRecord.createdAt,
                onOpenProfile: callbacks.onOpenProfile
            )

            if style != .minimal, let parent = entry.reply?.parent {
                PostReplyContextView(parent: parent)
            }

            if let text = post.safeRecord.text, !text.isEmpty {
                PostTextContent(
                    text: text,
                    onTapThread: callbacks.onTapThread,
                    onOpenProfile: callbacks.onOpenProfile,
                    onOpenURL: callbacks.onOpenURL
                )
            }

            if style != .minimal, let embed = post.embed {
                PostEmbedView(
                    embed: embed,
                    onTapImage: callbacks.onTapImage,
                    onPlayVideo: callbacks.onPlayVideo
                )
            }

            if style == .full || style == .compact {
                PostActionBar(
                    replyCount: post.replyCount,
                    repostCount: post.repostCount,
                    likeCount: post.likeCount,
                    isLiked: callbacks.isLiked,
                    isReposted: callbacks.isReposted,
                    callbacks: callbacks
                )
            }
        }
    }
}

// MARK: - Helpers

/// Converts @mentions and URLs in post text to tappable attributed links.
func postAttributedString(from text: String) -> AttributedString {
    var attributed = AttributedString(text)
    guard text.contains("@") || text.contains("://") || text.contains("www.") else { return attributed }

    let nsRange = NSRange(text.startIndex..., in: text)

    let mentionRegex = MentionTextRegex.shared
    for match in mentionRegex.matches(in: text, range: nsRange).reversed() {
        guard let range = Range(match.range, in: text),
              let attrRange = Range(match.range, in: attributed) else { continue }
        let handle = String(text[range].dropFirst())
        attributed[attrRange].link = URL(string: "mention://\(handle)")
        attributed[attrRange].foregroundColor = Color.skyPrimary
        attributed[attrRange].underlineStyle = .single
    }

    if let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) {
        for match in detector.matches(in: text, range: nsRange).reversed() {
            guard let url = match.url,
                  let attrRange = Range(match.range, in: attributed) else { continue }
            attributed[attrRange].link = url
            attributed[attrRange].foregroundColor = Color.skyPrimary
            attributed[attrRange].underlineStyle = .single
        }
    }

    return attributed
}

/// Regex for matching @mention patterns in post text.
private enum MentionTextRegex {
    static let shared = try! NSRegularExpression(
        pattern: "@[a-zA-Z0-9_]([a-zA-Z0-9_.-]*[a-zA-Z0-9_])?"
    )
}
