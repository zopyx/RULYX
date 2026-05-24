import SwiftUI

struct PostAuthorHeader: View {
    let author: RichAuthor
    let createdAt: String?
    var onOpenProfile: ((String) -> Void)?
    var avatarSize: CGFloat = 36

    private var displayName: String {
        author.displayName ?? author.handle ?? ""
    }

    private var handle: String? {
        author.handle
    }

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
