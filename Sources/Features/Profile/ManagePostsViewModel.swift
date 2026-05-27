import Foundation

@MainActor
final class ManagePostsViewModel: ObservableObject {
    @Published private(set) var posts: [RichFeedEntry] = []
    @Published private(set) var isLoading = false
    @Published private(set) var isLoadingMore = false
    @Published private(set) var hasMore = true
    @Published private(set) var isDeleting = false
    @Published private(set) var deleteProgress: (current: Int, total: Int)?
    @Published var errorMessage: String?
    @Published var searchText = ""
    @Published var fromDate: Date?
    @Published var toDate: Date?
    @Published var relativeDateFilter: RelativeDateOption?
    @Published var isSelecting = false
    @Published var selectedURIs: Set<String> = []
    @Published var pendingDeleteEntry: RichFeedEntry?
    @Published var showBulkConfirm = false
    @Published var nuclearDeleteLevel = 0

    enum RelativeDateOption: String, CaseIterable {
        case today, last7, last30, lastYear, allTime

        var label: String {
            "profile.manage_posts.relative.\(rawValue)"
        }

        var dateFrom: Date? {
            let cal = Calendar.current
            switch self {
            case .today: return cal.startOfDay(for: Date())
            case .last7: return cal.date(byAdding: .day, value: -7, to: cal.startOfDay(for: Date()))
            case .last30: return cal.date(byAdding: .day, value: -30, to: cal.startOfDay(for: Date()))
            case .lastYear: return cal.date(byAdding: .year, value: -1, to: cal.startOfDay(for: Date()))
            case .allTime: return nil
            }
        }
    }

    var sortedFilteredPosts: [RichFeedEntry] {
        var result = posts

        if !searchText.isEmpty {
            let query = searchText.lowercased()
            result = result.filter { entry in
                entry.post.safeRecord.text?.lowercased().contains(query) ?? false
            }
        }

        if let fromDate {
            result = result.filter { entry in
                guard let d = parseDate(entry.post.safeRecord.createdAt) else { return false }
                return d >= fromDate
            }
        }

        if let toDate {
            result = result.filter { entry in
                guard let d = parseDate(entry.post.safeRecord.createdAt) else { return false }
                return d <= toDate
            }
        }

        result.sort { a, b in
            let dateA = parseDate(a.post.safeRecord.createdAt) ?? .distantPast
            let dateB = parseDate(b.post.safeRecord.createdAt) ?? .distantPast
            return dateA > dateB
        }

        return result
    }

    var selectedPosts: [RichFeedEntry] {
        posts.filter { selectedURIs.contains($0.post.uri) }
    }

    var allPostURIs: [String] {
        posts.map(\.post.uri)
    }

    private var cursor: String?
    private let did: String

    init(did: String) {
        self.did = did
    }

    func loadPosts(account: AppAccount, appPassword: String, using client: LiveBlueskyClient) async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            guard !Task.isCancelled else { return }
            let response = try await client.fetchRichFeed(did: did, cursor: nil, account: account, appPassword: appPassword)
            posts = response.feed
            cursor = response.cursor
            hasMore = cursor != nil
        } catch {
            guard !AppError.isCancellation(error) else { return }
            errorMessage = AppError.userMessage(from: error)
            AppLogger.moderation.error("Failed to load posts: \(error.localizedDescription, privacy: .public)")
        }
    }

    func loadMore(account: AppAccount, appPassword: String, using client: LiveBlueskyClient) async {
        guard !isLoadingMore, let cursor else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        do {
            guard !Task.isCancelled else { return }
            let response = try await client.fetchRichFeed(did: did, cursor: cursor, account: account, appPassword: appPassword)
            posts += response.feed
            self.cursor = response.cursor
            hasMore = response.cursor != nil
        } catch {
            guard !AppError.isCancellation(error) else { return }
            errorMessage = AppError.userMessage(from: error)
            AppLogger.moderation.error("Failed to load more posts: \(error.localizedDescription, privacy: .public)")
        }
    }

    func refresh(account: AppAccount, appPassword: String, using client: LiveBlueskyClient) async {
        guard !isLoading else { return }
        let oldCursor = cursor
        let oldHasMore = hasMore
        cursor = nil
        hasMore = true
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            guard !Task.isCancelled else { return }
            let response = try await client.fetchRichFeed(did: did, cursor: nil, account: account, appPassword: appPassword)
            posts = response.feed
            cursor = response.cursor
            hasMore = cursor != nil
        } catch {
            guard !AppError.isCancellation(error) else { return }
            cursor = oldCursor
            hasMore = oldHasMore
            errorMessage = AppError.userMessage(from: error)
            AppLogger.moderation.error("Failed to refresh posts: \(error.localizedDescription, privacy: .public)")
        }
    }

    func deletePost(_ entry: RichFeedEntry, account: AppAccount, appPassword: String, using client: LiveBlueskyClient) async {
        let uri = entry.post.uri
        posts.removeAll { $0.post.uri == uri }
        selectedURIs.remove(uri)
        pendingDeleteEntry = nil

        do {
            _ = try await client.deleteRecord(recordURI: uri, account: account, appPassword: appPassword)
        } catch {
            if !posts.contains(where: { $0.post.uri == uri }) {
                posts.append(entry)
            }
            AppLogger.moderation.error("Failed to delete post: \(error.localizedDescription, privacy: .public)")
        }
    }

    func deleteSelectedPosts(account: AppAccount, appPassword: String, using client: LiveBlueskyClient) async {
        let uris = selectedURIs
        guard !uris.isEmpty else { return }
        isDeleting = true
        deleteProgress = (0, uris.count)
        defer {
            isDeleting = false
            deleteProgress = nil
        }

        for (index, uri) in uris.enumerated() {
            guard !Task.isCancelled else { return }
            posts.removeAll { $0.post.uri == uri }
            deleteProgress = (index + 1, uris.count)
            do {
                _ = try await client.deleteRecord(recordURI: uri, account: account, appPassword: appPassword)
            } catch {
                AppLogger.moderation.error("Failed to delete post \(uri): \(error.localizedDescription, privacy: .public)")
            }
        }

        selectedURIs = []
        showBulkConfirm = false
        isSelecting = false
    }

    func deleteAllPosts(account: AppAccount, appPassword: String, using client: LiveBlueskyClient) async {
        isDeleting = true
        deleteProgress = nil
        nuclearDeleteLevel = 0

        var allURIs: [String] = []
        var pageCursor: String?

        while !Task.isCancelled {
            do {
                let response = try await client.fetchRichFeed(did: did, cursor: pageCursor, account: account, appPassword: appPassword)
                allURIs += response.feed.map(\.post.uri)
                guard let next = response.cursor else { break }
                pageCursor = next
            } catch {
                guard !AppError.isCancellation(error) else { return }
                AppLogger.moderation.error("Failed to load page for nuclear delete: \(error.localizedDescription, privacy: .public)")
                break
            }
        }

        guard !allURIs.isEmpty else {
            isDeleting = false
            return
        }

        deleteProgress = (0, allURIs.count)

        for (index, uri) in allURIs.enumerated() {
            guard !Task.isCancelled else { return }
            posts.removeAll { $0.post.uri == uri }
            deleteProgress = (index + 1, allURIs.count)
            do {
                _ = try await client.deleteRecord(recordURI: uri, account: account, appPassword: appPassword)
            } catch {
                AppLogger.moderation.error("Failed to delete post \(uri): \(error.localizedDescription, privacy: .public)")
            }
        }

        selectedURIs = []
        isSelecting = false
        isDeleting = false
        deleteProgress = nil
    }

    func selectAllFiltered() {
        selectedURIs = Set(sortedFilteredPosts.map(\.post.uri))
    }

    func deselectAll() {
        selectedURIs = []
    }

    func exitSelectMode() {
        isSelecting = false
        selectedURIs = []
    }
}
