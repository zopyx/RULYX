import SwiftUI

// MARK: - AccountChip

/// A compact, tappable chip showing the active account's avatar and display name
/// with a chevron-down indicator. Used in toolbar/header areas to indicate the
/// currently active account and to trigger account switching.
/// Adapts to iOS 26 glass effect when available, falls back to thin material.
struct AccountChip: View {
    /// The account to display.
    let account: AppAccount
    /// Optional URL for the account's avatar image.
    let avatarURL: URL?
    @ScaledMetric(relativeTo: .caption) private var avatarSize = 22.0

    // MARK: - Body

    var body: some View {
        HStack(spacing: 8) {
            avatarView

            Text(account.displayName)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)

            Image(systemName: "chevron.down")
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 12)
        .background {
            if #available(iOS 26, *) {
                Color.clear
                    .glassEffect(.regular.interactive(), in: .rect(cornerRadius: .infinity))
            } else {
                Color.clear.background(.thinMaterial, in: Capsule())
            }
        }
    }

    // MARK: - Private Helpers

    @ViewBuilder
    private var avatarView: some View {
        if let avatarURL = avatarURL ?? account.avatarURL {
            AsyncImage(url: avatarURL) { image in
                image
                    .resizable()
                    .scaledToFill()
            } placeholder: {
                avatarPlaceholder
            }
            .frame(width: avatarSize, height: avatarSize)
            .clipShape(Circle())
        } else {
            avatarPlaceholder
        }
    }

    private var avatarPlaceholder: some View {
        Circle()
            .fill(Color.skyPrimary)
            .frame(width: avatarSize, height: avatarSize)
            .overlay {
                Text(account.displayName.prefix(1).uppercased())
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white)
            }
    }
}

#Preview {
    AccountChip(
        account: AppAccount(handle: "team-alpha.bsky.social", displayName: "Team Alpha"),
        avatarURL: nil
    )
}
