import Foundation

@MainActor
final class UserPostsViewModel: ObservableObject {
    @Published private(set) var posts: [RichFeedEntry] = []
    @Published private(set) var isLoading = false
    @Published private(set) var isLoadingMore = false
    @Published private(set) var hasMore = true
    @Published var errorMessage: String?
    @Published var searchText = ""
    @Published var fromDate: Date?
    @Published var toDate: Date?

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

    private var cursor: String?
    private let did: String

    init(did: String) {
        self.did = did
    }

    func refresh(account: AppAccount, appPassword: String, using client: LiveBlueskyClient) async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        let oldCursor = cursor
        let oldHasMore = hasMore
        cursor = nil
        hasMore = true
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

    func loadMorePosts(account: AppAccount, appPassword: String, using client: LiveBlueskyClient) async {
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

    func exportCSV() -> String {
        let header = "uri,author_did,author_handle,text,created_at,reply_count,repost_count,like_count"
        let rows = sortedFilteredPosts.map { entry -> String in
            let p = entry.post
            let author = p.safeAuthor
            let text = (p.safeRecord.text ?? "").replacingOccurrences(of: "\"", with: "\"\"")
            let fields = [
                p.uri,
                author.did ?? "",
                author.handle ?? "",
                "\"\(text)\"",
                p.safeRecord.createdAt ?? "",
                "\(p.replyCount ?? 0)",
                "\(p.repostCount ?? 0)",
                "\(p.likeCount ?? 0)",
            ]
            return fields.joined(separator: ",")
        }
        return ([header] + rows).joined(separator: "\n")
    }

    func exportJSON() -> Data {
        let objects = sortedFilteredPosts.map { entry -> [String: Any] in
            let p = entry.post
            let author = p.safeAuthor
            return [
                "uri": p.uri,
                "author_did": author.did ?? "",
                "author_handle": author.handle ?? "",
                "author_display_name": author.displayName ?? "",
                "text": p.safeRecord.text ?? "",
                "created_at": p.safeRecord.createdAt ?? "",
                "reply_count": p.replyCount ?? 0,
                "repost_count": p.repostCount ?? 0,
                "like_count": p.likeCount ?? 0,
                "has_images": p.embed?.images?.isEmpty == false,
                "has_video": p.embed?.video != nil,
            ] as [String: Any]
        }
        return (try? JSONSerialization.data(withJSONObject: objects, options: [.prettyPrinted, .sortedKeys])) ?? Data()
    }
}
