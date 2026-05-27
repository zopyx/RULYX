import SwiftUI

// MARK: - PostAuthorHeader

/// The author section of a post row: avatar, display name, handle, and relative timestamp.
/// Tapping the avatar or name triggers `onOpenProfile` with the author's DID/handle.
struct PostAuthorHeader: View {
    /// The author data to display.
    let author: RichAuthor
    /// ISO 8601 timestamp string for relative date display.
    let createdAt: String?
    /// Triggered when the avatar or display name is tapped, passing the DID/handle.
    var onOpenProfile: ((String) -> Void)?
    /// Diameter of the avatar circle.
    var avatarSize: CGFloat = 36

    // MARK: - Private Helpers

    /// The display name falling back to the handle if unavailable.
    private var displayName: String {
        author.displayName ?? author.handle ?? ""
    }

    /// The author's handle, if available.
    private var handle: String? {
        author.handle
    }

    // MARK: - Body

    var body: some View {
        HStack(spacing: 8) {
            Button {
                onOpenProfile?(author.handle ?? author.did ?? "")
            } label: {
                if let url = author.avatar.flatMap(URL.init) {
                    ThumbnailImageView(url: url, maxPixelSize: 72) {
                        Circle().fill(Color.skyPrimary.opacity(0.16))
                    }
                    .scaledToFill()
                    .frame(width: avatarSize, height: avatarSize)
                    .clipShape(Circle())
                } else {
                    Circle()
                        .fill(Color.skyPrimary.opacity(0.16))
                        .frame(width: avatarSize, height: avatarSize)
                        .overlay {
                            Text(displayName.prefix(1).uppercased())
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
                    Text(displayName)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                        .foregroundStyle(.primary)
                    if let handle {
                        Text("@\(handle)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .buttonStyle(.plain)

            Spacer()

            if let created = createdAt, let date = parseDate(created) {
                Text(relativeTimeString(from: date))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }
}
