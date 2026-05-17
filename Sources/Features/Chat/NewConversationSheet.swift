import SwiftUI

struct NewConversationSheet: View {
    @EnvironmentObject var accountStore: AccountStore
    @EnvironmentObject var blueskyClient: LiveBlueskyClient
    @EnvironmentObject var chatStore: ChatStore
    @Environment(\.dismiss) private var dismiss
    @State private var searchQuery = ""
    @State private var searchResults: [BlueskyActor] = []
    @State private var isSearching = false
    @State private var selectedActor: BlueskyActor?
    @State private var isCreating = false

    let onComplete: (ChatConversation?) -> Void

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
                            ActorSearchRow(actor: actor, isSelected: selectedActor?.did == actor.did)
                                .contentShape(Rectangle())
                                .onTapGesture { selectedActor = actor }
                        }
                    }
                }
            }
            .navigationTitle(loc("chat.new.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(loc("actions.cancel")) {
                        dismiss()
                        onComplete(nil)
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if let selectedActor {
                        Button(loc("chat.new.start")) {
                            Task { await startConversation(actor: selectedActor) }
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
            let response = try await blueskyClient.searchActors(query: searchQuery, account: account, appPassword: pw)
            searchResults = response
        } catch {
            searchResults = []
        }
    }

    private func startConversation(actor: BlueskyActor) async {
        guard let account = accountStore.activeAccount else {
            dismiss()
            onComplete(nil)
            return
        }

        let appPassword = accountStore.appPassword(for: account)
        chatStore.setAccount(account, appPassword: appPassword)
        isCreating = true
        let convo = await chatStore.getOrCreateConvo(memberDID: actor.did)
        isCreating = false
        dismiss()
        onComplete(convo)
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
