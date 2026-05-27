import Foundation

/// Manages the moderation dashboard: lists grouped by kind, active profile info, and blocking counts.
///
/// Supports caching via `DashboardCache` so the dashboard loads instantly from disk
/// while quietly refreshing data in the background.
@MainActor
final class ListsViewModel: ObservableObject {
    // MARK: - Properties

    /// All moderation lists grouped by their kind (moderation, reference, etc.).
    @Published private(set) var listsByKind: [BlueskyList.Kind: [BlueskyList]] = [:]
    /// Profile of the currently active account.
    @Published private(set) var activeProfile: BlueskyProfile?
    /// Number of accounts this user is blocking.
    @Published private(set) var blockingCount: Int?
    /// Number of accounts blocking this user.
    @Published private(set) var blockedByCount: Int?
    /// True while the initial load is in progress (no cache).
    @Published private(set) var isLoading = false
    /// True while a manual refresh is in progress.
    @Published private(set) var isRefreshing = false
    /// True when the displayed data was loaded from cache.
    @Published private(set) var isFromCache = false
    /// User-facing error message.
    @Published var errorMessage: String?

    // MARK: - Public Methods

    /// Resets all state to initial values.
    func reset() {
        listsByKind = [:]
        activeProfile = nil
        blockingCount = nil
        blockedByCount = nil
        isLoading = false
        isRefreshing = false
        errorMessage = nil
    }

    /// Loads the dashboard data — lists, profile, blocking counts.
    ///
    /// Behavior:
    /// - If cached data exists, applies it immediately (`isFromCache = true`) then refreshes.
    /// - Deferred cache hit: `isLoading` stays false; only `isRefreshing` is set for explicit refresh.
    /// - If no cache, sets `isLoading = true` and shows a spinner.
    /// - Persists updated cache after network fetch completes.
    func load(
        for account: AppAccount?,
        appPassword: String?,
        using client: LiveBlueskyClient,
        isExplicitRefresh: Bool = false
    ) async {
        guard let account else {
            listsByKind = [:]
            activeProfile = nil
            blockingCount = nil
            blockedByCount = nil
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

        // Fire all four fetches in parallel
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
            guard !AppError.isCancellation(error) else { return }
            if listsByKind.isEmpty {
                listsByKind = [:]
                errorMessage = AppError.userMessage(from: error)
            }
        }

        activeProfile = try? await profileTask
        blockingCount = try? await blockingTask
        blockedByCount = try? await blockedByTask

        persistCache(forKey: cacheKey)
        isFromCache = false
        isLoading = false
        isRefreshing = false
    }

    /// Applies a cached `DashboardCacheData` snapshot to all published properties.
    private func applyCached(_ cached: DashboardCacheData) {
        listsByKind = Dictionary(grouping: cached.lists, by: \.kind)
        activeProfile = cached.profile
        blockingCount = cached.blockingCount
        blockedByCount = cached.blockedByCount
    }

    /// Persists the current state to `DashboardCache` for the given key.
    private func persistCache(forKey key: String) {
        let data = DashboardCacheData(
            lists: Array(listsByKind.values.flatMap(\.self)),
            profile: activeProfile,
            blockingCount: blockingCount,
            blockedByCount: blockedByCount
        )
        DashboardCache.save(data, forKey: key)
    }

    /// Adds a new list to the in-memory collection and updates the cache.
    func addList(_ list: BlueskyList) {
        var updated = listsByKind
        updated[list.kind, default: []].append(list)
        updated[list.kind]?.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        listsByKind = updated
        persistCache(forKey: didCacheKey ?? "")
    }

    /// Replaces an existing list with an updated version, preserving sort order.
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

    // MARK: - Private Properties

    /// Resolves the cache key from the current active profile.
    private var didCacheKey: String? {
        activeProfile?.did ?? activeProfile?.handle
    }
}
