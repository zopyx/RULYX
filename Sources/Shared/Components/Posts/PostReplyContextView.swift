import SwiftUI

struct PostReplyContextView: View {
    let parent: RichPost

    @EnvironmentObject private var localizationManager: LocalizationManager

    var body: some View {
        let parentAuthor = parent.safeAuthor
        VStack(spacing: 0) {
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
    }
}
