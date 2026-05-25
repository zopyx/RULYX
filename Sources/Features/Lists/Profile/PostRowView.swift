import SwiftUI

struct PostRowView: View {
    let entry: RichFeedEntry
    let style: PostDisplayStyle
    let callbacks: PostRowCallbacks

    init(entry: RichFeedEntry, style: PostDisplayStyle = .full, callbacks: PostRowCallbacks = PostRowCallbacks()) {
        self.entry = entry
        self.style = style
        self.callbacks = callbacks
    }

    private var post: RichPost {
        entry.post
    }

    private var author: RichAuthor {
        post.safeAuthor
    }

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
                    onOpenProfile: callbacks.onOpenProfile
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

func mentionAttributedString(from text: String) -> AttributedString {
    var attributed = AttributedString(text)
    guard text.contains("@") else { return attributed }

    let regex = MentionTextRegex.shared
    let nsRange = NSRange(text.startIndex..., in: text)
    for match in regex.matches(in: text, range: nsRange).reversed() {
        guard let range = Range(match.range, in: text),
              let attrRange = Range(match.range, in: attributed) else { continue }
        let handle = String(text[range].dropFirst())
        attributed[attrRange].link = URL(string: "mention://\(handle)")
        attributed[attrRange].foregroundColor = Color.skyPrimary
        attributed[attrRange].underlineStyle = .single
    }
    return attributed
}

private enum MentionTextRegex {
    static let shared = try! NSRegularExpression(
        pattern: "@[a-zA-Z0-9_]([a-zA-Z0-9_.-]*[a-zA-Z0-9_])?"
    )
}
