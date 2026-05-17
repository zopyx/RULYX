import SwiftUI

struct AccountRowView: View {
    let account: AppAccount
    let isActive: Bool
    @ScaledMetric(relativeTo: .body) private var avatarSize = 40.0

    private var entrywayLabel: String? {
        guard let entryway = account.entrywayURL else { return nil }
        let host = entryway.host ?? ""
        guard host != "bsky.social" else { return nil }
        return host
    }

    var body: some View {
        HStack(spacing: 12) {
            avatarView

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(account.displayName)
                        .font(.headline)
                    if let label = account.label {
                        Text(label)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(Color.skyPrimary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background {
                                if #available(iOS 26, *) {
                                    Color.clear.glassEffect(.regular.tint(.skyPrimary), in: .rect(cornerRadius: .infinity))
                                } else {
                                    Color.clear.background(Color.skyPrimary.opacity(0.1), in: Capsule())
                                }
                            }
                    }
                }
                HStack(spacing: 6) {
                    Text(account.handle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    if let label = entrywayLabel {
                        Text(label)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background {
                                if #available(iOS 26, *) {
                                    Color.clear.glassEffect(.regular, in: .rect(cornerRadius: .infinity))
                                } else {
                                    Color.clear.background(Color.secondary.opacity(0.15), in: Capsule())
                                }
                            }
                    }
                }
            }

            Spacer()

            if isActive {
                Text(loc("account.active"))
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background {
                        if #available(iOS 26, *) {
                            Color.clear.glassEffect(.regular.tint(.skyPrimary), in: .rect(cornerRadius: .infinity))
                        } else {
                            Color.clear.background(Color.skyPrimary.opacity(0.14), in: Capsule())
                        }
                    }
                    .foregroundStyle(.white)
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var avatarView: some View {
        if let avatarURL = account.avatarURL {
            AsyncImage(url: avatarURL) { image in
                image
                    .resizable()
                    .scaledToFill()
            } placeholder: {
                avatarPlaceholder
            }
            .frame(width: avatarSize, height: avatarSize)
            .clipShape(Circle())
            .overlay {
                Circle()
                    .stroke(Color.white.opacity(0.18), lineWidth: 1)
            }
        } else {
            avatarPlaceholder
        }
    }

    private var avatarPlaceholder: some View {
        Circle()
            .fill(isActive ? Color.skyPrimary : Color.gray.opacity(0.25))
            .frame(width: avatarSize, height: avatarSize)
            .overlay {
                Text(account.displayName.prefix(1).uppercased())
                    .font(.headline)
                    .foregroundStyle(.white)
            }
    }
}

#Preview {
    List {
        AccountRowView(
            account: AppAccount(handle: "team-alpha.bsky.social", displayName: "Team Alpha"),
            isActive: true
        )
    }
}
