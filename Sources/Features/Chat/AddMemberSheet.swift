import SwiftUI

/// Sheet for adding a member to an existing group conversation.
/// Searches Bluesky actors and adds the selected one to the group.
struct AddMemberSheet: View {
    @EnvironmentObject var chatStore: ChatStore
    @EnvironmentObject var accountStore: AccountStore
    @EnvironmentObject var container: BlueskyServiceContainerWrapper
    @EnvironmentObject private var localizationManager: LocalizationManager
    @Environment(\.dismiss) private var dismiss

    let conversation: ChatConversation

    @State private var searchQuery = ""
    @State private var searchResults: [BlueskyActor] = []
    @State private var isSearching = false
    @State private var isAdding = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(.secondary)
                        TextField(loc("chat.add_member.placeholder"), text: $searchQuery)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                            .onSubmit { Task { await search() } }
                    }
                }

                if let error = errorMessage {
                    Section {
                        Text(error)
                            .foregroundStyle(.red)
                            .font(.caption)
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
                            HStack {
                                actorAvatar(actor, size: 40)
                                VStack(alignment: .leading) {
                                    Text(actor.displayName ?? actor.handle)
                                        .font(.headline)
                                    Text("@\(actor.handle)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                if isAdding {
                                    ProgressView()
                                        .controlSize(.small)
                                } else {
                                    Button(loc("chat.add_member.add")) {
                                        Task { await addMember(actor) }
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                                }
                            }
                        }
                    }
                }
            }
            .pageTitle(loc("chat.add_member.title"))
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(loc("actions.done")) { dismiss() }
                }
            }
        }
    }

    private func search() async {
        guard !searchQuery.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        isSearching = true
        errorMessage = nil
        defer { isSearching = false }

        guard let account = accountStore.activeAccount else { return }
        do {
            let pw = accountStore.appPassword(for: account)
            let response = try await container.profile.searchActors(query: searchQuery, account: account, appPassword: pw)
            // Filter out already-present members
            let existingDIDs = Set(conversation.members.map(\.did))
            searchResults = response.filter { !existingDIDs.contains($0.did) }
        } catch {
            searchResults = []
        }
    }

    private func addMember(_ actor: BlueskyActor) async {
        isAdding = true
        errorMessage = nil
        await chatStore.addMember(convoId: conversation.id, memberDID: actor.did)
        isAdding = false
        if chatStore.error != nil {
            errorMessage = chatStore.error?.localizedDescription
            chatStore.error = nil
        } else {
            dismiss()
        }
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
