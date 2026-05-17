import SwiftUI

struct UserSearchSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var accountStore: AccountStore
    @EnvironmentObject private var blueskyClient: LiveBlueskyClient

    @State private var searchQuery = ""
    @State private var results: [BlueskyActor] = []
    @State private var isSearching = false
    @State private var selectedActor: BlueskyActor?
    @FocusState private var searchFocused: Bool

    var body: some View {
        NavigationStack {
            List {
                Section {
                    TextField(loc("usersearch.placeholder"), text: $searchQuery)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($searchFocused)
                }

                if results.isEmpty, !searchQuery.isEmpty, !isSearching {
                    ContentUnavailableView(
                        loc("usersearch.no_results"),
                        systemImage: "magnifyingglass",
                        description: Text(verbatim: loc("usersearch.no_results_desc"))
                    )
                }

                ForEach(results) { actor in
                    NavigationLink {
                        BlueskyProfileView(
                            member: BlueskyListMember(recordURI: "search:\(actor.did)", actor: actor),
                            list: nil
                        )
                        .environmentObject(accountStore)
                        .environmentObject(blueskyClient)
                    } label: {
                        BlueskyActorRow(actor: actor)
                    }
                }

                if isSearching {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle(loc("usersearch.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(loc("actions.close")) { dismiss() }
                }
            }
        }
        .onChange(of: searchQuery) { _, query in
            Task { await performSearch(query) }
        }
        .task {
            try? await Task.sleep(for: .milliseconds(300))
            searchFocused = true
        }
    }

    private func performSearch(_ query: String) async {
        guard let account = accountStore.activeAccount,
              let appPassword = accountStore.appPassword(for: account)
        else { return }

        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            results = []
            isSearching = false
            return
        }

        isSearching = true
        do {
            results = try await blueskyClient.searchActorsFull(query: trimmed, account: account, appPassword: appPassword)
        } catch {
            results = []
        }
        isSearching = false
    }
}
