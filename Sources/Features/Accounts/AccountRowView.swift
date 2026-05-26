import SwiftUI

struct AccountRowView: View {
    let account: AppAccount
    let isActive: Bool
    let isDeactivated: Bool

    init(account: AppAccount, isActive: Bool, isDeactivated: Bool = false) {
        self.account = account
        self.isActive = isActive
        self.isDeactivated = isDeactivated
    }

    @ScaledMetric(relativeTo: .body) private var avatarSize = 40.0

    private var entrywayLabel: String? {
        guard let entryway = account.entrywayURL else { return nil }
        let host = entryway.host ?? ""
        guard host != "bsky.social" else { return nil }
        return host
    }

    @EnvironmentObject private var localizationManager: LocalizationManager
    var body: some View {
        HStack(spacing: 12) {
            avatarView

            VStack(alignment: .leading, spacing: 2) {
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
                Text(account.handle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                let hasEntryway = entrywayLabel != nil
                if hasEntryway || isActive {
                    HStack(spacing: 6) {
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
                        if isActive {
                            HStack(spacing: 4) {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.caption2.weight(.semibold))
                                Text(loc("account.active"))
                                    .font(.caption2.weight(.semibold))
                            }
                            .foregroundStyle(.white)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background {
                                if #available(iOS 26, *) {
                                    Color.clear.glassEffect(.regular.tint(.skyPrimary), in: .rect(cornerRadius: .infinity))
                                } else {
                                    Color.clear.background(Color.skyPrimary.opacity(0.14), in: Capsule())
                                }
                            }
                        }
                    }
                }
            }

            Spacer()

            if isDeactivated {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.octagon.fill")
                        .font(.caption)
                    Text(loc("account.deactivated"))
                        .font(.caption.weight(.semibold))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background {
                    if #available(iOS 26, *) {
                        Color.clear.glassEffect(.regular.tint(.red), in: .rect(cornerRadius: .infinity))
                    } else {
                        Color.clear.background(Color.red.opacity(0.14), in: Capsule())
                    }
                }
                .foregroundStyle(.red)
            }
        }
        .padding(.vertical, 2)
        .opacity(isDeactivated ? 0.6 : 1)
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
            isActive: true,
            isDeactivated: false
        )
    }
}
