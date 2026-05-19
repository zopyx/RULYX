import SwiftUI

extension ListDetailView {
    struct ListDetailHeaderSection: View {
        let currentList: BlueskyList
        let isOwnedList: Bool
        let ownerActor: BlueskyActor?
        @Binding var imagePreview: ImagePreviewCollection?

        var body: some View {
            Section {
                HStack(alignment: .top, spacing: 14) {
                    if let avatarURL = currentList.avatarURL {
                        Button {
                            imagePreview = ImagePreviewCollection(urls: [avatarURL], initialIndex: 0)
                        } label: {
                            ThumbnailImageView(url: avatarURL, maxPixelSize: 96) {
                                avatarPlaceholder
                            }
                            .frame(width: 48, height: 48)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(Color.white.opacity(0.18), lineWidth: 1)
                            }
                        }
                        .buttonStyle(.plain)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text(currentList.name)
                            .appFont(.title)
                            .lineLimit(3)
                        if !currentList.description.isEmpty, currentList.description != currentList.name {
                            Text(currentList.description)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        if !isOwnedList, let ownerActor {
                            NavigationLink {
                                BlueskyProfileView(
                                    member: BlueskyListMember(
                                        recordURI: "owner:\(ownerActor.did)",
                                        actor: ownerActor
                                    ),
                                    list: nil
                                )
                            } label: {
                                HStack(spacing: 10) {
                                    if let avatarURL = ownerActor.avatarURL {
                                        ThumbnailImageView(url: avatarURL, maxPixelSize: 56) {
                                            Circle()
                                                .fill(Color.skyPrimary.opacity(0.16))
                                        }
                                        .frame(width: 28, height: 28)
                                        .clipShape(Circle())
                                    } else {
                                        Circle()
                                            .fill(Color.skyPrimary.opacity(0.16))
                                            .frame(width: 28, height: 28)
                                            .overlay {
                                                Text(ownerActor.displayName?.prefix(1).uppercased() ?? "?")
                                                    .font(.caption.weight(.bold))
                                                    .foregroundStyle(Color.skyPrimary)
                                            }
                                    }
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(ownerActor.displayName ?? ownerActor.handle)
                                            .font(.subheadline.weight(.semibold))
                                        Text("@\(ownerActor.handle)")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                            .padding(.top, 8)
                        }
                    }
                }
                .padding(.vertical, 4)
            }
        }

        private var avatarPlaceholder: some View {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.skyPrimary.opacity(0.12))
                .overlay {
                    Image(systemName: currentList.kind.symbolName)
                        .font(.title3)
                        .foregroundStyle(Color.skyPrimary)
                }
        }
    }
}
