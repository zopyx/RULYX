import SwiftUI

struct TrendDetectionView: View {
    @EnvironmentObject private var accountStore: AccountStore
    @EnvironmentObject private var blueskyClient: LiveBlueskyClient
    @State private var flaggedAccounts: [(BlueskyActor, String)] = []
    @State private var isLoading = false

    var body: some View {
        List {
            if isLoading {
                Section {
                    SkeletonRow()
                    SkeletonRow()
                    SkeletonRow()
                }
            }

            if flaggedAccounts.isEmpty, !isLoading {
                ContentUnavailableView(loc("trend.no_trends"), systemImage: "chart.line.flatten.circle", description: Text(loc("trend.no_trends_desc")))
            }

            ForEach(flaggedAccounts.indices, id: \.self) { index in
                let (actor, reason) = flaggedAccounts[index]
                NavigationLink {
                    BlueskyProfileView(member: BlueskyListMember(recordURI: "trend:\(actor.did)", actor: actor), list: nil)
                        .environmentObject(accountStore)
                        .environmentObject(blueskyClient)
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(actor.title).font(.headline)
                        Text(actor.handle).font(.subheadline).foregroundStyle(.secondary)
                        Text(reason).font(.caption).foregroundStyle(.orange)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(loc("trend.title"))
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(loc("trend.scan")) { Task { await scan() } }.disabled(isLoading)
            }
        }
        .task { await scan() }
    }

    private func scan() async {
        guard let account = accountStore.activeAccount,
              let appPassword = accountStore.appPassword(for: account) else { return }
        isLoading = true
        flaggedAccounts = []
        let did = account.did ?? account.handle

        do {
            let followers = try await blueskyClient.fetchFollowers(actor: did, account: account, appPassword: appPassword)
            for actor in followers {
                var reasons: [String] = []
                if actor.isNew { reasons.append(loc("trend.new_account")) }
                if !reasons.isEmpty {
                    flaggedAccounts.append((actor, reasons.joined(separator: " · ")))
                }
            }
            flaggedAccounts.sort { $0.0.createdAt ?? .distantPast > $1.0.createdAt ?? .distantPast }
        } catch {
            // Silent fail — data just won't load
        }
        isLoading = false
    }
}

#Preview {
    NavigationStack { TrendDetectionView().environmentObject(AccountStore(preview: true)).environmentObject(PreviewBlueskyClient()) }
}
