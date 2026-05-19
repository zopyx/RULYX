import Foundation

struct NotificationEntry: Identifiable {
    var notification: NotificationItem
    let relatedPostURI: String?
    let relatedPost: RichPost?

    var id: String {
        notification.id
    }
}

@MainActor
final class NotificationViewModel: ObservableObject {
    @Published private(set) var entries: [NotificationEntry] = []
    @Published private(set) var state: TimelineState = .initialLoading
    @Published private(set) var unreadCount = 0

    private var cursor: String?

    func load(account: AppAccount, appPassword: String, using client: LiveBlueskyClient) async {
        guard state == .initialLoading else { return }
        do {
            let response = try await client.fetchNotifications(cursor: nil, account: account, appPassword: appPassword)
            let items = response.notifications
            cursor = response.cursor
            entries = await buildEntries(for: items, account: account, appPassword: appPassword, using: client)
            state = entries.isEmpty ? .empty : (cursor == nil ? .exhausted : .loaded)
        } catch {
            guard !AppError.isCancellation(error) else { return }
            state = .failed(AppError.userMessage(from: error))
        }
    }

    func refresh(account: AppAccount, appPassword: String, using client: LiveBlueskyClient) async {
        state = .refreshing
        do {
            let response = try await client.fetchNotifications(cursor: nil, account: account, appPassword: appPassword)
            let items = response.notifications
            cursor = response.cursor
            entries = await buildEntries(for: items, account: account, appPassword: appPassword, using: client)
            state = entries.isEmpty ? .empty : (cursor == nil ? .exhausted : .loaded)
        } catch {
            guard !AppError.isCancellation(error) else { return }
            state = .failed(AppError.userMessage(from: error))
        }
    }

    func loadMore(account: AppAccount, appPassword: String, using client: LiveBlueskyClient) async {
        guard let cursor, state != .loadingMore else { return }
        state = .loadingMore
        do {
            let response = try await client.fetchNotifications(cursor: cursor, account: account, appPassword: appPassword)
            let items = response.notifications
            self.cursor = response.cursor
            let newEntries = await buildEntries(for: items, account: account, appPassword: appPassword, using: client)
            entries += newEntries
            state = response.cursor == nil ? .exhausted : .loaded
        } catch {
            guard !AppError.isCancellation(error) else { return }
            state = .loadMoreFailed(AppError.userMessage(from: error))
        }
    }

    func markAllRead(account: AppAccount, appPassword: String, using client: LiveBlueskyClient) async {
        do {
            try await client.updateSeen(at: .now, account: account, appPassword: appPassword)
            for i in entries.indices {
                entries[i].notification.isRead = true
            }
            unreadCount = 0
        } catch {
            AppLogger.moderation.error("Failed to mark notifications as read: \(error.localizedDescription, privacy: .public)")
        }
    }

    func updateUnreadCount(account: AppAccount, appPassword: String, using client: LiveBlueskyClient) async {
        guard let count = try? await client.getUnreadCount(account: account, appPassword: appPassword) else { return }
        unreadCount = count
    }

    func reset() {
        entries = []
        state = .initialLoading
        cursor = nil
        unreadCount = 0
    }

    private func buildEntries(
        for notifications: [NotificationItem],
        account: AppAccount,
        appPassword: String,
        using client: LiveBlueskyClient
    ) async -> [NotificationEntry] {
        let posts = await fetchRelevantPosts(for: notifications, account: account, appPassword: appPassword, using: client)
        return notifications.map { notification in
            let uri = postURI(for: notification)
            return NotificationEntry(
                notification: notification,
                relatedPostURI: uri,
                relatedPost: uri.flatMap { posts[$0] }
            )
        }
    }

    private func fetchRelevantPosts(
        for notifications: [NotificationItem],
        account _: AppAccount,
        appPassword _: String,
        using client: LiveBlueskyClient
    ) async -> [String: RichPost] {
        let postURIs = Array(Set(notifications.compactMap { postURI(for: $0) }))
        guard !postURIs.isEmpty else { return [:] }

        var resolvedPosts: [String: RichPost] = [:]

        do {
            let posts = try await client.fetchPosts(uris: postURIs)
            for post in posts {
                resolvedPosts[post.uri] = post
            }
        } catch {
            AppLogger.moderation.error("Batch notification post fetch failed: \(error.localizedDescription, privacy: .public)")
        }

        let missingURIs = postURIs.filter { resolvedPosts[$0] == nil }
        guard !missingURIs.isEmpty else { return resolvedPosts }

        await withTaskGroup(of: (String, RichPost?).self) { group in
            for uri in missingURIs {
                group.addTask {
                    do {
                        let posts = try await client.fetchPosts(uris: [uri])
                        return (uri, posts.first)
                    } catch {
                        return (uri, nil)
                    }
                }
            }

            for await (uri, post) in group {
                if let post {
                    resolvedPosts[uri] = post
                }
            }
        }

        return resolvedPosts
    }

    private func postURI(for notification: NotificationItem) -> String? {
        switch notification.reason {
        case "like", "repost":
            notification.reasonSubject
        case "reply", "quote", "mention":
            notification.uri
        case "follow":
            nil
        default:
            notification.reasonSubject ?? notification.uri
        }
    }
}
