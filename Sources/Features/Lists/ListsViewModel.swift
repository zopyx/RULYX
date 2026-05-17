import Foundation

@MainActor
final class ListsViewModel: ObservableObject {
    @Published private(set) var listsByKind: [BlueskyList.Kind: [BlueskyList]] = [:]
    @Published private(set) var activeProfile: BlueskyProfile?
    @Published private(set) var blockingCount = 0
    @Published private(set) var blockedByCount = 0
    @Published private(set) var isLoading = false
    @Published private(set) var isRefreshing = false
    @Published private(set) var isFromCache = false
    @Published var errorMessage: String?

    func reset() {
        listsByKind = [:]
        activeProfile = nil
        blockingCount = 0
        blockedByCount = 0
        isLoading = false
        isRefreshing = false
        errorMessage = nil
    }

    func load(
        for account: AppAccount?,
        appPassword: String?,
        using client: LiveBlueskyClient,
        isExplicitRefresh: Bool = false
    ) async {
        guard let account else {
            listsByKind = [:]
            activeProfile = nil
            blockingCount = 0
            blockedByCount = 0
            errorMessage = nil
            return
        }

        let cacheKey = account.did ?? account.handle
        let hasCache: Bool
        if let cached = DashboardCache.load(forKey: cacheKey) {
            applyCached(cached)
            isFromCache = true
            hasCache = true
        } else {
            hasCache = false
        }

        if !hasCache { isLoading = true }
        if isExplicitRefresh { isRefreshing = true }
        errorMessage = nil

        async let listsTask = client.fetchLists(for: account, appPassword: appPassword)
        async let profileTask = client.fetchProfile(
            did: account.did ?? account.handle,
            account: account,
            appPassword: appPassword
        )
        async let blockingTask = client.fetchBlockingCount(for: account)
        async let blockedByTask = client.fetchBlockedByCount(for: account)

        do {
            listsByKind = try await Dictionary(grouping: listsTask, by: \.kind)
        } catch {
            if listsByKind.isEmpty {
                listsByKind = [:]
                errorMessage = AppError.userMessage(from: error)
            }
        }

        activeProfile = try? await profileTask
        if let count = try? await blockingTask { blockingCount = count }
        if let count = try? await blockedByTask { blockedByCount = count }

        persistCache(forKey: cacheKey)
        isFromCache = false
        isLoading = false
        isRefreshing = false
    }

    private func applyCached(_ cached: DashboardCacheData) {
        listsByKind = Dictionary(grouping: cached.lists, by: \.kind)
        activeProfile = cached.profile
        blockingCount = cached.blockingCount
        blockedByCount = cached.blockedByCount
    }

    private func persistCache(forKey key: String) {
        let data = DashboardCacheData(
            lists: Array(listsByKind.values.flatMap(\.self)),
            profile: activeProfile,
            blockingCount: blockingCount,
            blockedByCount: blockedByCount
        )
        DashboardCache.save(data, forKey: key)
    }

    func addList(_ list: BlueskyList) {
        var updated = listsByKind
        updated[list.kind, default: []].append(list)
        updated[list.kind]?.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        listsByKind = updated
        persistCache(forKey: didCacheKey ?? "")
    }

    func updateList(_ updatedList: BlueskyList) {
        var updated = listsByKind
        guard var lists = updated[updatedList.kind],
              let index = lists.firstIndex(where: { $0.id == updatedList.id })
        else {
            return
        }

        lists[index] = updatedList
        updated[updatedList.kind] = lists
        listsByKind = updated
        persistCache(forKey: didCacheKey ?? "")
    }

    private var didCacheKey: String? {
        activeProfile?.did ?? activeProfile?.handle
    }
}
