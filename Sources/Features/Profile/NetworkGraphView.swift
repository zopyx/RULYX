import SwiftUI

struct NetworkGraphView: View {
    @EnvironmentObject private var accountStore: AccountStore
    @EnvironmentObject private var blueskyClient: LiveBlueskyClient
    @EnvironmentObject private var localizationManager: LocalizationManager
    @State private var accountA: BlueskyActor?
    @State private var accountB: BlueskyActor?
    @State private var aFollowers: Set<String> = []
    @State private var aFollowing: Set<String> = []
    @State private var bFollowers: Set<String> = []
    @State private var bFollowing: Set<String> = []
    @State private var isLoading = false
    @State private var statusMessage: String?
    @State private var searchQueryA = ""
    @State private var searchQueryB = ""
    @State private var searchResultsA: [BlueskyActor] = []
    @State private var searchResultsB: [BlueskyActor] = []

    private var mutualFollowers: [String] {
        Array(aFollowers.intersection(bFollowers)).sorted()
    }

    private var mutualFollowing: [String] {
        Array(aFollowing.intersection(bFollowing)).sorted()
    }

    private var aFollowsB: Bool {
        aFollowing.contains(accountB?.did ?? "")
    }

    private var bFollowsA: Bool {
        bFollowing.contains(accountA?.did ?? "")
    }

    var body: some View {
        List {
            Section {
                SearchField(query: $searchQueryA, results: $searchResultsA, onSelect: { actor in
                    accountA = actor
                    searchQueryA = actor.handle
                }, accountStore: accountStore, blueskyClient: blueskyClient)
                if let a = accountA {
                    Label(a.handle, systemImage: "person.fill")
                }
            } header: {
                Text("network.account_a")
            }

            Section {
                SearchField(query: $searchQueryB, results: $searchResultsB, onSelect: { actor in
                    accountB = actor
                    searchQueryB = actor.handle
                }, accountStore: accountStore, blueskyClient: blueskyClient)
                if let b = accountB {
                    Label(b.handle, systemImage: "person.fill")
                }
            } header: {
                Text("network.account_b")
            }

            if let a = accountA, let b = accountB {
                Section {
                    LabeledContent("network.mutual_followers", value: "\(mutualFollowers.count)")
                    LabeledContent("network.mutual_following", value: "\(mutualFollowing.count)")
                    LabeledContent(
                        String.localized("network.follows_relationship", replacements: ["handle1": a.handle, "handle2": b.handle]),
                        value: aFollowsB ? String(localized: "network.yes") : String(localized: "network.no")
                    )
                    LabeledContent(
                        String.localized("network.follows_relationship", replacements: ["handle1": b.handle, "handle2": a.handle]),
                        value: bFollowsA ? String(localized: "network.yes") : String(localized: "network.no")
                    )
                } header: {
                    Text("network.overlap")
                }

                if !mutualFollowers.isEmpty {
                    Section {
                        ForEach(mutualFollowers.prefix(20), id: \.self) { did in
                            Text(did).font(.caption.monospaced())
                        }
                        if mutualFollowers.count > 20 {
                            Text(verbatim: String(localized: "network.more_count").replacingOccurrences(of: "{count}", with: "\(mutualFollowers.count - 20)")).font(.caption).foregroundStyle(.secondary)
                        }
                    } header: {
                        Text("network.following_both")
                    }
                }
            }

            Section {
                Button("network.analyze") { Task { await analyze() } }
                    .disabled(accountA == nil || accountB == nil || isLoading)
                    .foregroundStyle(Color.skyPrimary)
                    .accessibilityHint("network.analyze.hint")
            }

            if isLoading {
                Section {
                    SkeletonRow()
                    SkeletonRow()
                    SkeletonRow()
                }
            }

            if let statusMessage {
                Text(statusMessage).font(.caption).foregroundStyle(.secondary)
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("network.title")
    }

    private func analyze() async {
        guard let account = accountStore.activeAccount,
              let appPassword = accountStore.appPassword(for: account),
              let a = accountA, let b = accountB else { return }
        isLoading = true
        statusMessage = nil

        do {
            async let aFol = blueskyClient.fetchFollowers(actor: a.did, account: account, appPassword: appPassword)
            async let aFing = blueskyClient.fetchFollowing(actor: a.did, account: account, appPassword: appPassword)
            async let bFol = blueskyClient.fetchFollowers(actor: b.did, account: account, appPassword: appPassword)
            async let bFing = blueskyClient.fetchFollowing(actor: b.did, account: account, appPassword: appPassword)
            let (af, afg, bf, bfg) = try await (aFol, aFing, bFol, bFing)
            aFollowers = Set(af.map(\.did))
            aFollowing = Set(afg.map(\.did))
            bFollowers = Set(bf.map(\.did))
            bFollowing = Set(bfg.map(\.did))
        } catch {
            statusMessage = AppError.userMessage(from: error)
        }
        isLoading = false
    }
}

private struct SearchField: View {
    @Binding var query: String
    @Binding var results: [BlueskyActor]
    let onSelect: (BlueskyActor) -> Void
    let accountStore: AccountStore
    let blueskyClient: LiveBlueskyClient

    var body: some View {
        TextField("network.search_placeholder", text: $query)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .task(id: query) {
                guard query.count >= 2 else { results = []
                    return
                }
                try? await Task.sleep(for: .milliseconds(300))
                guard let account = accountStore.activeAccount,
                      let appPassword = accountStore.appPassword(for: account) else { return }
                if let actors = try? await blueskyClient.searchActors(query: query, account: account, appPassword: appPassword) {
                    results = actors
                }
            }

        if !results.isEmpty {
            ForEach(results.prefix(5)) { actor in
                Button { onSelect(actor)
                    results = []
                } label: {
                    Label(actor.handle, systemImage: "person").foregroundStyle(.primary)
                }
                .accessibilityHint("network.select.hint")
            }
        }
    }
}

#Preview {
    NavigationStack { NetworkGraphView().environmentObject(AccountStore(preview: true)).environmentObject(PreviewBlueskyClient()) }
}
