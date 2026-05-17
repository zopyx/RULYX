import SwiftUI

struct AccountSummaryCard: View {
    let account: AppAccount
    let avatarURL: URL?
    @ScaledMetric(relativeTo: .title2) private var avatarSize = 60.0

    var body: some View {
        HStack(spacing: 14) {
            avatarView

            VStack(alignment: .leading, spacing: 3) {
                Text(account.displayName)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(account.handle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.skyPrimary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(LinearGradient.cardAccentGradient)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.skyPrimary.opacity(0.14), lineWidth: 1)
        }
    }

    @ViewBuilder
    private var avatarView: some View {
        if let avatarURL {
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
                    .stroke(Color.white.opacity(0.24), lineWidth: 1)
            }
        } else {
            avatarPlaceholder
        }
    }

    private var avatarPlaceholder: some View {
        Circle()
            .fill(
                LinearGradient(
                    colors: [.skyPrimary, .skyAccent],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .frame(width: avatarSize, height: avatarSize)
            .overlay {
                Text(account.displayName.prefix(1).uppercased())
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.white)
            }
    }
}

#Preview {
    AccountSummaryCard(
        account: AppAccount(handle: "team-alpha.bsky.social", displayName: "Team Alpha"),
        avatarURL: nil
    )
}
