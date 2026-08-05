import SwiftUI

// MARK: - PostReplyContextView

/// A compact preview of the parent post in a reply chain: shows a vertical connector line,
/// the parent author's name + handle, the first two lines of their text, and a
/// compact preview of the first embedded image.
/// Placed above the reply composer or the replying post in a thread view.
struct PostReplyContextView: View {
    /// The parent post being replied to.
    let parent: RichPost

    @EnvironmentObject private var localizationManager: LocalizationManager

    // MARK: - Body

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
                            .font(.caption.weight(.semibold))
                            .lineLimit(1)
                            .foregroundStyle(.primary)
                        if let handle = parentAuthor.handle {
                            Text("@\(handle)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    if let text = parent.safeRecord.text, !text.isEmpty {
                        Text(text)
                            .font(.caption)
                            .lineLimit(2)
                            .foregroundStyle(.secondary)
                    }
                }
                if let image = parent.embed?.images?.first,
                   let imageURL = image.thumb.flatMap(URL.init) ?? image.fullsize.flatMap(URL.init)
                {
                    ThumbnailImageView(url: imageURL, maxPixelSize: 128) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.skyPrimary.opacity(0.08))
                    }
                    .scaledToFill()
                    .frame(width: 48, height: 48)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                }
            }
            .padding(8)
            .background(Color.skyPrimary.opacity(0.04), in: RoundedRectangle(cornerRadius: 6))

            Text(verbatim: "\(loc("profile.posts.replying_to")) \(parentAuthor.displayName ?? parentAuthor.handle ?? "")")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }
}
