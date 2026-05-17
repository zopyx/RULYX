import SwiftUI

struct PostRowView: View {
    let entry: RichFeedEntry
    var onTapThread: (() -> Void)?
    let onTapImage: (Int) -> Void
    var onPlayVideo: (() -> Void)?
    var onReply: (() -> Void)?
    var onLike: (() -> Void)?
    var onShowLikes: (() -> Void)?
    var isLiked: Bool = false
    var isReposted: Bool = false
    var onRepost: (() -> Void)?
    var onQuote: (() -> Void)?
    var onCopy: (() -> Void)?
    var onTranslate: (() -> Void)?
    var onDeletePost: (() -> Void)?
    var onOpenProfile: ((String) -> Void)?
    var onBlockAllLikers: (() -> Void)?
    var availableLikerTargetLists: [BlueskyList] = []
    var onAddAllLikersToList: ((BlueskyList) -> Void)?
    @Environment(\.openURL) private var openURL
    @State private var altTextToShow: String?

    private var post: RichPost {
        entry.post
    }

    private var author: RichAuthor {
        post.safeAuthor
    }

    private var moderationLikerTargetLists: [BlueskyList] {
        availableLikerTargetLists.filter { $0.kind == .moderation }
    }

    private var regularLikerTargetLists: [BlueskyList] {
        availableLikerTargetLists.filter { $0.kind == .regular }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Button {
                    onOpenProfile?(author.handle ?? author.did ?? "")
                } label: {
                    if let url = author.avatar.flatMap(URL.init) {
                        ThumbnailImageView(url: url, maxPixelSize: 72) {
                            Circle().fill(Color.skyPrimary.opacity(0.16))
                        }
                        .scaledToFill()
                        .frame(width: 36, height: 36)
                        .clipShape(Circle())
                    } else {
                        Circle()
                            .fill(Color.skyPrimary.opacity(0.16))
                            .frame(width: 36, height: 36)
                            .overlay {
                                Text((author.displayName ?? author.handle ?? "?").prefix(1).uppercased())
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(Color.skyPrimary)
                            }
                    }
                }
                .buttonStyle(.plain)
                Button {
                    onOpenProfile?(author.handle ?? author.did ?? "")
                } label: {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(author.displayName ?? author.handle ?? "")
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                            .foregroundStyle(.primary)
                        if let handle = author.handle {
                            Text("@\(handle)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .buttonStyle(.plain)
                Spacer()
                if let created = post.safeRecord.createdAt, let date = parseDate(created) {
                    Text(relativeTimeString(from: date))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            if let parent = entry.reply?.parent {
                let parentAuthor = parent.safeAuthor
                HStack(spacing: 6) {
                    Rectangle()
                        .fill(Color.gray.opacity(0.2))
                        .frame(width: 2)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 4) {
                            Text(parentAuthor.displayName ?? parentAuthor.handle ?? "")
                                .font(.caption2.weight(.semibold))
                                .lineLimit(1)
                            if let handle = parentAuthor.handle {
                                Text("@\(handle)")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                                    .lineLimit(1)
                            }
                        }
                        Text(parent.safeRecord.text ?? "")
                            .font(.caption2)
                            .lineLimit(2)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(8)
                .background(Color.skyPrimary.opacity(0.04), in: RoundedRectangle(cornerRadius: 6))
                Text(verbatim: "\(loc("profile.posts.replying_to")) \(parentAuthor.displayName ?? parentAuthor.handle ?? "")")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }

            Group {
                if let text = post.safeRecord.text, !text.isEmpty {
                    let textContent = Text(mentionAttributedString(from: text))
                        .font(.body)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .environment(\.openURL, OpenURLAction { url in
                            if url.scheme == "mention", let handle = url.host {
                                onOpenProfile?(handle)
                                return .handled
                            }
                            return .systemAction
                        })
                    if let onTapThread {
                        textContent
                            .contentShape(Rectangle())
                            .onTapGesture { onTapThread() }
                    } else {
                        textContent
                    }
                }
            }

            if let video = post.embed?.video {
                Button {
                    if let onPlayVideo {
                        onPlayVideo()
                    }
                } label: {
                    videoEmbedCard(video)
                }
                .buttonStyle(.plain)
            }

            if let images = post.embed?.images, !images.isEmpty {
                let isSingle = images.count == 1
                let cols = isSingle ? 1 : 2
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: cols), spacing: 4) {
                    ForEach(Array(images.prefix(4).enumerated()), id: \.offset) { index, item in
                        if let previewURL = item.fullsize.flatMap(URL.init) {
                            Button {
                                onTapImage(index)
                            } label: {
                                ThumbnailImageView(url: item.thumb.flatMap(URL.init) ?? previewURL, maxPixelSize: 512) {
                                    Rectangle().fill(Color.skyPrimary.opacity(0.08))
                                }
                                .aspectRatio(contentMode: isSingle ? .fit : .fill)
                                .frame(height: isSingle ? 300 : 130)
                                .clipped()
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                .overlay(alignment: .topLeading) {
                                    if let alt = item.alt, !alt.isEmpty {
                                        Button {
                                            altTextToShow = alt
                                        } label: {
                                            Text("ALT")
                                                .font(.caption2.weight(.bold))
                                                .foregroundStyle(.white)
                                                .padding(.horizontal, 6)
                                                .padding(.vertical, 3)
                                                .background(.black.opacity(0.5), in: Capsule())
                                        }
                                        .buttonStyle(.plain)
                                        .padding(6)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }

            if let external = post.embed?.external, let uri = external.uri, let url = URL(string: uri) {
                if external.isTenorEmbed, let gifURL = external.preferredInlineMediaURL {
                    InlineAnimatedMediaView(url: gifURL, allowsInteraction: true)
                        .overlay {
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.skyPrimary.opacity(0.12), lineWidth: 1)
                        }
                } else {
                    Button {
                        openURL(url)
                    } label: {
                        externalEmbedCard(external)
                    }
                    .buttonStyle(.plain)
                }
            }

            actionBar
        }
    }

    private var actionBar: some View {
        HStack(spacing: 24) {
            if let onReply {
                actionButton(
                    icon: "bubble.left",
                    count: post.replyCount,
                    action: onReply
                )
            }
            if let onRepost {
                Button(action: { onRepost() }) {
                    HStack(spacing: 4) {
                        Image(systemName: isReposted ? "repeat.circle.fill" : "repeat")
                            .font(.body.weight(.medium))
                        if let count = post.repostCount {
                            Text("\(count)")
                                .font(.callout)
                        }
                    }
                    .foregroundStyle(isReposted ? Color.green : Color.gray.opacity(0.6))
                }
                .buttonStyle(.plain)
            }
            HStack(spacing: 4) {
                Button(action: { onLike?() }) {
                    Image(systemName: isLiked ? "heart.fill" : "heart")
                        .font(.body.weight(.medium))
                        .foregroundStyle(isLiked ? Color.red : Color.gray.opacity(0.6))
                }
                if let count = post.likeCount {
                    Button(action: { onShowLikes?() }) {
                        Text("\(count)")
                            .font(.callout)
                    }
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(.tertiary)
            if let onQuote {
                actionButton(
                    icon: "quote.bubble",
                    count: nil,
                    action: onQuote
                )
            }
            Spacer()
            if let likeCount = post.likeCount, likeCount > 0 {
                Menu {
                    if let onBlockAllLikers {
                        Button {
                            onBlockAllLikers()
                        } label: {
                            Label(loc("post.block_likers"), systemImage: "hand.raised.slash")
                        }
                    }
                    if let onAddAllLikersToList, !availableLikerTargetLists.isEmpty {
                        Menu {
                            if !moderationLikerTargetLists.isEmpty {
                                Menu(loc("lists.moderation_lists")) {
                                    ForEach(moderationLikerTargetLists) { list in
                                        Button {
                                            onAddAllLikersToList(list)
                                        } label: {
                                            Label(list.name, systemImage: list.kind.symbolName)
                                        }
                                    }
                                }
                            }
                            if !regularLikerTargetLists.isEmpty {
                                Menu(loc("lists.lists")) {
                                    ForEach(regularLikerTargetLists) { list in
                                        Button {
                                            onAddAllLikersToList(list)
                                        } label: {
                                            Label(list.name, systemImage: list.kind.symbolName)
                                        }
                                    }
                                }
                            }
                        } label: {
                            Label(loc("post.add_likers_to_list"), systemImage: "text.badge.plus")
                        }
                    }
                    if let onCopy {
                        Button(action: onCopy) {
                            Label(loc("post.copy"), systemImage: "doc.on.doc")
                        }
                    }
                    if let onTranslate {
                        Button(action: onTranslate) {
                            Label(loc("post.translate"), systemImage: "globe")
                        }
                    }
                    if let onDeletePost {
                        Divider()
                        Button(role: .destructive, action: onDeletePost) {
                            Label(loc("post.delete"), systemImage: "trash")
                        }
                    }
                } label: {
                    Image(systemName: "gearshape")
                        .font(.body.weight(.medium))
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .foregroundStyle(.tertiary)
    }

    private func externalEmbedCard(_ external: RichEmbedExternal) -> some View {
        HStack(spacing: 12) {
            if let thumb = external.thumb, let url = URL(string: thumb) {
                ThumbnailImageView(url: url, maxPixelSize: 512) {
                    RoundedRectangle(cornerRadius: 10).fill(Color.skyPrimary.opacity(0.08))
                }
                .scaledToFill()
                .frame(width: 96, height: 96)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }

            VStack(alignment: .leading, spacing: 6) {
                if let title = external.title, !title.isEmpty {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                }
                if let description = external.description, !description.isEmpty {
                    Text(description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }
                if let host = external.uri.flatMap(URL.init)?.host, !host.isEmpty {
                    Label(host, systemImage: "link")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(10)
        .background(Color.skyPrimary.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.skyPrimary.opacity(0.12), lineWidth: 1)
        }
    }

    private func videoEmbedCard(_ video: RichEmbedVideo) -> some View {
        ZStack {
            if let thumb = video.thumbnail, let url = URL(string: thumb) {
                ThumbnailImageView(url: url, maxPixelSize: 720) {
                    Rectangle().fill(Color.skyPrimary.opacity(0.08))
                }
                .scaledToFill()
            } else {
                LinearGradient(
                    colors: [Color.skyPrimary.opacity(0.22), Color.skyPrimary.opacity(0.08)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .overlay {
                    Image(systemName: "film.stack")
                        .font(.system(size: 34, weight: .medium))
                        .foregroundStyle(.white.opacity(0.92))
                }
            }

            Image(systemName: "play.circle.fill")
                .font(.system(size: 44))
                .foregroundStyle(.white)
                .shadow(radius: 4)
        }
        .frame(height: 200)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private func actionButton(icon: String, count: Int?, action: (() -> Void)?) -> some View {
        if let action {
            Button(action: action) {
                HStack(spacing: 4) {
                    Image(systemName: icon)
                        .font(.body.weight(.medium))
                    if let count {
                        Text("\(count)")
                            .font(.callout)
                    }
                }
            }
            .buttonStyle(.plain)
        } else {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.body.weight(.medium))
                if let count {
                    Text("\(count)")
                        .font(.callout)
                }
            }
        }
    }
}

func mentionAttributedString(from text: String) -> AttributedString {
    var attributed = AttributedString(text)
    guard let regex = try? NSRegularExpression(pattern: "@[a-zA-Z0-9_]([a-zA-Z0-9_.-]*[a-zA-Z0-9_])?") else { return attributed }
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
