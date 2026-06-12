import SwiftUI

/// Sheet for starting a new chat conversation — 1:1 or group.
/// Supports searching for users by handle/display name, selecting
/// multiple actors for group creation, and providing an optional group name.
struct NewConversationSheet: View {
    @EnvironmentObject var accountStore: AccountStore
    @EnvironmentObject var blueskyClient: LiveBlueskyClient
    @EnvironmentObject var chatStore: ChatStore
    @Environment(\.dismiss) private var dismiss
    @State private var searchQuery = ""
    @State private var searchResults: [BlueskyActor] = []
    @State private var isSearching = false
    @State private var selectedActors: Set<String> = []
    @State private var isGroup = false
    @State private var groupName = ""
    @State private var isCreating = false
    @State private var errorMessage: String?

    let onComplete: (ChatConversation?) -> Void
    @EnvironmentObject private var localizationManager: LocalizationManager

    /// The actor selected for 1:1 conversation (only one allowed).
    private var selectedActor: BlueskyActor? {
        let selected = searchResults.filter { selectedActors.contains($0.did) }
        return selected.count == 1 ? selected.first : nil
    }

    var body: some View {
        NavigationStack {
            List {
                // Chat type toggle
                Section {
                    Toggle(isOn: $isGroup) {
                        Label(loc("chat.new.group"), systemImage: "person.3")
                    }
                    .onChange(of: isGroup) { _, _ in
                        if !isGroup { selectedActors = [] }
                    }
                }

                if isGroup {
                    Section {
                        TextField(loc("chat.new.group_name_placeholder"), text: $groupName)
                    } header: {
                        Text(loc("chat.new.group_name"))
                    }
                }

                // Search
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

                if isSearching {
                    Section {
                        HStack {
                            Spacer()
                            ProgressView()
                            Spacer()
                        }
                    }
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .font(.subheadline)
                            .foregroundStyle(.red)
                    }
                }

                if !searchResults.isEmpty {
                    Section(isGroup ? loc("chat.new.select_multiple") : loc("chat.new.results")) {
                        ForEach(searchResults) { actor in
                            ActorSearchRow(
                                actor: actor,
                                isSelected: selectedActors.contains(actor.did),
                                showCheckmark: isGroup
                            )
                            .contentShape(Rectangle())
                            .onTapGesture {
                                if isGroup {
                                    if selectedActors.contains(actor.did) {
                                        selectedActors.remove(actor.did)
                                    } else {
                                        selectedActors.insert(actor.did)
                                    }
                                } else {
                                    selectedActors = [actor.did]
                                }
                            }
                        }
                    }
                }
            }
            .pageTitle(isGroup ? loc("chat.new.group") : loc("chat.new.title"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(loc("actions.cancel")) {
                        dismiss()
                        onComplete(nil)
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    let isDisabled = isCreating || selectedActors.isEmpty || (isGroup && groupName.trimmingCharacters(in: .whitespaces).isEmpty)
                    Button(isGroup ? loc("chat.new.create_group") : loc("chat.new.start")) {
                        Task { await createConversation() }
                    }
                    .disabled(isDisabled)
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
            let response = try await blueskyClient.searchActors(query: searchQuery, account: account, appPassword: pw)
            searchResults = response
        } catch {
            searchResults = []
        }
    }

    private func createConversation() async {
        guard let account = accountStore.activeAccount else {
            dismiss()
            onComplete(nil)
            return
        }

        let appPassword = accountStore.appPassword(for: account)
        chatStore.setAccount(account, appPassword: appPassword)
        isCreating = true
        errorMessage = nil

        let memberDIDs = Array(selectedActors)

        if isGroup {
            // For groups, use getConvoForMembers with all members.
            // The API creates the conversation if it doesn't exist.
            let convo = await chatStore.getOrCreateConvo(memberDIDs: memberDIDs)
            // If there's a group name, try to set it.
            let name = groupName.trimmingCharacters(in: .whitespaces)
            if let convo, !name.isEmpty {
                await chatStore.editGroupName(convoId: convo.id, name: name)
            }
            isCreating = false
            dismiss()
            onComplete(convo)
        } else {
            let convo = await chatStore.getOrCreateConvo(memberDID: memberDIDs.first ?? "")
            isCreating = false
            dismiss()
            onComplete(convo)
        }
    }
}

private struct ActorSearchRow: View {
    let actor: BlueskyActor
    let isSelected: Bool
    var showCheckmark: Bool = false

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
                Image(systemName: showCheckmark ? "checkmark.circle.fill" : "checkmark.circle.fill")
                    .foregroundStyle(Color.skyPrimary)
            }
        }
    }
}
