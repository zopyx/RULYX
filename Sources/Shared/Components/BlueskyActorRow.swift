import SwiftUI

struct BlueskyActorRow<Extra: View>: View {
    let actor: BlueskyActor
    let extra: Extra

    @ScaledMetric(relativeTo: .body) private var avatarSize: CGFloat = 40

    init(actor: BlueskyActor, @ViewBuilder extra: () -> Extra) {
        self.actor = actor
        self.extra = extra()
    }

    var body: some View {
        HStack(spacing: 12) {
            avatarView

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(actor.title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    extra
                }
                Text(actor.handle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if let description = actor.description, !description.isEmpty {
                    Text(description)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }

            Spacer()
        }
        .padding(.vertical, 10)
        .accessibilityLabel(loc("actor_row.label").replacingOccurrences(of: "{title}", with: actor.title).replacingOccurrences(of: "{handle}", with: actor.handle))
    }

    @ViewBuilder
    private var avatarView: some View {
        if let avatarURL = actor.avatarURL {
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
            .fill(Color.skyPrimary.opacity(0.16))
            .frame(width: avatarSize, height: avatarSize)
            .overlay {
                Text(actor.title.prefix(1).uppercased())
                    .font(.headline)
                    .foregroundStyle(Color.skyPrimary)
            }
    }
}

extension BlueskyActorRow where Extra == EmptyView {
    init(actor: BlueskyActor) {
        self.actor = actor
        extra = EmptyView()
    }
}

#Preview {
    List {
        BlueskyActorRow(
            actor: BlueskyActor(did: "did:plc:demo", handle: "alice.bsky.social", displayName: "Alice Chen")
        )
    }
}
