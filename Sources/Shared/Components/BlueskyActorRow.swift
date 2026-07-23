import SwiftUI

extension EnvironmentValues {
    @Entry var showActorDescriptions: Bool = false
}

// MARK: - BlueskyActorRow

/// A standard row displaying a Bluesky actor: avatar, title (display name), handle,
/// optional description, and an `Extra` view for badges, labels, or trailing content.
///
/// Generic parameter `Extra` allows callers to inject additional content (e.g. a "Bot" badge).
/// When no extra is needed, use the convenience initializer `init(actor:)`.
struct BlueskyActorRow<Extra: View>: View {
    /// The actor to display.
    let actor: BlueskyActor
    /// Optional extra view injected by the caller.
    let extra: Extra

    @ScaledMetric(relativeTo: .body) private var avatarSize: CGFloat = 36

    // MARK: - Init

    init(actor: BlueskyActor, @ViewBuilder extra: () -> Extra) {
        self.actor = actor
        self.extra = extra()
    }

    @EnvironmentObject private var localizationManager: LocalizationManager
    @Environment(\.showActorDescriptions) private var showActorDescriptions

    // MARK: - Body

    var body: some View {
        HStack(spacing: 10) {
            avatarView

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(actor.title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    extra
                }
                Text(actor.handle)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                if let description = actor.description, !description.isEmpty {
                    if showActorDescriptions {
                        Text(description)
                            .font(.caption)
                            .foregroundStyle(.primary)
                            .lineLimit(3)
                    }
                }
            }

            Spacer()
        }
        .padding(.vertical, 2)
        .accessibilityLabel(String.localized("actor_row.label", replacements: ["title": actor.title, "handle": actor.handle]))
    }

    // MARK: - Private Helpers

    @ViewBuilder
    private var avatarView: some View {
        if actor.avatarURL != nil {
            FreshAvatarImage(url: actor.avatarURL) {
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
    /// Convenience initializer when no extra content is needed.
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
