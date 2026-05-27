import SwiftUI

// MARK: - ActorSearchResultRow

/// A row in actor search results with a selection checkbox, actor info via `BlueskyActorRow`,
/// and an add button. Used in list member management and batch operation target selection.
struct ActorSearchResultRow: View {
    /// The actor to display.
    let actor: BlueskyActor
    /// Whether the actor is currently selected.
    let isSelected: Bool
    /// Whether an add operation is in progress.
    let isAdding: Bool
    /// Toggles the selection state.
    let toggleSelection: () -> Void
    /// Performs the add action for this actor.
    let addAction: () -> Void
    @EnvironmentObject private var localizationManager: LocalizationManager

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
