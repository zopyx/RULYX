import SwiftUI

/// Sheet for starting a new chat conversation — search for users by
/// handle/display name, select one or more, and create a DM or group.
///
/// Single selection → 1:1 DM via `getOrCreateConvo`
/// Multi selection (2+) → Group via `getOrCreateGroupConvo`
struct NewConversationSheet: View {
    @EnvironmentObject var accountStore: AccountStore
    @EnvironmentObject var container: BlueskyServiceContainerWrapper
    @EnvironmentObject var chatStore: ChatStore
    @Environment(\.dismiss) private var dismiss
    @State private var searchQuery = ""
    @State private var searchResults: [BlueskyActor] = []
    @State private var isSearching = false
    @State private var selectedActors: Set<BlueskyActor> = []
    @State private var isCreating = false

    let onComplete: (ChatConversation?) -> Void
    @EnvironmentObject private var localizationManager: LocalizationManager

    private var isMultiSelect: Bool { selectedActors.count >= 2 }
    private var confirmationTitle: String {
        isMultiSelect ? loc("chat.group.create") : loc("chat.new.start")
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(.secondary)
                        TextField(loc("chat.new.search_placeholder"), text: $searchQuery)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                            .onSubmit { Task { await search() } }
                    }
                }

                if !selectedActors.isEmpty {
                    Section(loc("chat.new.selected")) {
                        ForEach(Array(selectedActors)) { actor in
                            HStack {
                                actorAvatar(actor, size: 32)
                                VStack(alignment: .leading) {
                                    Text(actor.displayName ?? actor.handle)
                                        .font(.subheadline.weight(.semibold))
                                    Text("@\(actor.handle)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Button {
                                    selectedActors.remove(actor)
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundStyle(.tertiary)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }

                if isSearching {
                    Section {
                        HStack {
                            Spacer()
                            ProgressView()
                            Spacer()
                        }
                    }
                }

                if !searchResults.isEmpty {
                    Section(loc("chat.new.results")) {
                        ForEach(searchResults) { actor in
                            ActorSearchRow(
                                actor: actor,
                                isSelected: selectedActors.contains(actor)
                            )
                            .contentShape(Rectangle())
                            .onTapGesture {
                                if selectedActors.contains(actor) {
                                    selectedActors.remove(actor)
                                } else {
                                    selectedActors.insert(actor)
                                }
                            }
                        }
                    }
                }
            }
            .pageTitle(isMultiSelect
                ? String.localized("chat.group.create.title", replacements: ["n": "\(selectedActors.count)"])
                : loc("chat.new.title"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(loc("actions.cancel")) {
                        dismiss()
                        onComplete(nil)
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if !selectedActors.isEmpty {
                        Button(confirmationTitle) {
                            Task { await startConversation() }
                        }
                        .disabled(isCreating)
                    }
                }
            }
        }
    }

    private func search() async {
        guard !searchQuery.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        isSearching = true
        defer { isSearching = false }

        guard let account = accountStore.activeAccount else { return }
        do {
            let pw = accountStore.appPassword(for: account)
            let response = try await container.profile.searchActors(query: searchQuery, account: account, appPassword: pw)
            searchResults = response
        } catch {
            searchResults = []
        }
    }

    private func startConversation() async {
        guard let account = accountStore.activeAccount else {
            dismiss()
            onComplete(nil)
            return
        }

        let appPassword = accountStore.appPassword(for: account)
        chatStore.setAccount(account, appPassword: appPassword)
        isCreating = true

        let convo: ChatConversation?
        if isMultiSelect {
            let dids = selectedActors.map(\.did)
            convo = await chatStore.getOrCreateGroupConvo(memberDIDs: dids)
        } else if let actor = selectedActors.first {
            convo = await chatStore.getOrCreateConvo(memberDID: actor.did)
        } else {
            convo = nil
        }

        isCreating = false
        dismiss()
        onComplete(convo)
    }

    @ViewBuilder
    private func actorAvatar(_ actor: BlueskyActor, size: CGFloat) -> some View {
        if let url = actor.avatarURL {
            AsyncImage(url: url) { phase in
                switch phase {
                case let .success(image):
                    image.resizable().scaledToFill()
                default:
                    Image(systemName: "person.circle.fill")
                        .resizable()
                }
            }
            .frame(width: size, height: size)
            .clipShape(Circle())
        } else {
            Image(systemName: "person.circle.fill")
                .resizable()
                .frame(width: size, height: size)
                .foregroundStyle(.tertiary)
        }
    }
}

private struct ActorSearchRow: View {
    let actor: BlueskyActor
    let isSelected: Bool

    var body: some View {
        HStack {
            if let url = actor.avatarURL {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case let .success(image):
                        image.resizable().scaledToFill()
                    default:
                        Image(systemName: "person.circle.fill")
                            .resizable()
                    }
                }
                .frame(width: 40, height: 40)
                .clipShape(Circle())
            } else {
                Image(systemName: "person.circle.fill")
                    .resizable()
                    .frame(width: 40, height: 40)
                    .foregroundStyle(.tertiary)
            }

            VStack(alignment: .leading) {
                Text(actor.displayName ?? actor.handle)
                    .font(.headline)
                Text("@\(actor.handle)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Color.skyPrimary)
            }
        }
    }
}
