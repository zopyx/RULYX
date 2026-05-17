import SwiftUI

struct ActorSearchResultRow: View {
    let actor: BlueskyActor
    let isSelected: Bool
    let isAdding: Bool
    let toggleSelection: () -> Void
    let addAction: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: toggleSelection) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? Color.skyPrimary : Color.secondary.opacity(0.45))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isSelected ? "Deselect \(actor.handle)" : "Select \(actor.handle)")
            .accessibilityHint(loc("actor_search.toggle.hint"))

            BlueskyActorRow(actor: actor)

            Button {
                addAction()
            } label: {
                if isAdding {
                    ProgressView()
                        .frame(width: 24, height: 24)
                } else {
                    Image(systemName: "plus.circle.fill")
                        .font(.title3)
                        .foregroundStyle(Color.skyPrimary)
                }
            }
            .buttonStyle(.plain)
            .disabled(isAdding)
            .accessibilityLabel(loc("actor_search.add"))
            .accessibilityHint(loc("actor_search.add_to_list.hint"))
        }
    }
}

#Preview {
    List {
        ActorSearchResultRow(
            actor: BlueskyActor(did: "did:plc:demo", handle: "alice.bsky.social", displayName: "Alice Chen"),
            isSelected: false,
            isAdding: false,
            toggleSelection: {},
            addAction: {}
        )
    }
}
