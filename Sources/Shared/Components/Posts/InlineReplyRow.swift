import SwiftUI

/// A minimal inline reply preview used beneath timeline posts when inline
/// thread expansion is toggled. Shows a connector line, avatar, author name,
/// truncated text, and a like count badge.
struct InlineReplyRow: View {
    let node: ThreadNode
    var onNavigateToThread: (() -> Void)?

    var body: some View {
        let author = node.post.author ?? RichAuthor(did: "", handle: "unknown", displayName: nil, avatar: nil)
        let record = node.post.record ?? RichRecord(text: "", createdAt: "")
        let likeCount = node.post.likeCount ?? 0

        Button {
            onNavigateToThread?()
        } label: {
            HStack(alignment: .top, spacing: 8) {
                Rectangle()
                    .fill(Color.gray.opacity(0.2))
                    .frame(width: 2)
                    .frame(maxHeight: .infinity)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 4) {
                        if let avatarURL = author.avatar.flatMap(URL.init) {
                            AsyncImage(url: avatarURL) { image in
                                image.resizable().scaledToFill()
                            } placeholder: {
                                Circle().fill(Color.skyPrimary.opacity(0.16))
                            }
                            .frame(width: 20, height: 20)
                            .clipShape(Circle())
                        }
                        Text(author.displayName ?? author.handle ?? "")
                            .font(.caption.weight(.semibold))
                            .lineLimit(1)
                        if let handle = author.handle {
                            Text("@\(handle)")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                        }
                        Spacer()
                        if likeCount > 0 {
                            HStack(spacing: 2) {
                                Image(systemName: "heart")
                                    .font(.caption2)
                                Text("\(likeCount)")
                                    .font(.caption2)
                            }
                            .foregroundStyle(.tertiary)
                        }
                    }
                    if let text = record.text, !text.isEmpty {
                        Text(text)
                            .font(.subheadline)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                            .foregroundStyle(.primary)
                    }
                }
            }
        }
        .buttonStyle(.plain)
        .padding(.vertical, 4)
    }
}
