import Foundation

/// A notification with an optional resolved related post.
struct NotificationEntry: Identifiable {
    var notification: NotificationItem
    let relatedPostURI: String?
    let relatedPost: RichPost?

    var id: String {
        notification.id
    }
}

/// Manages the notification list: loading, pagination, marking as read, and unread count.
///
/// State machine: `.initialLoading → .loadingMore → .loaded | .exhausted | .failed | .loadMoreFailed | .refreshing | .empty`
/// Each notification is enriched with its related post (if applicable) by batch-fetching post data.
@MainActor
final class NotificationViewModel: ObservableObject {
    // MARK: - Properties

    /// Loaded notifications, newest first.
    @Published private(set) var entries: [NotificationEntry] = []
    /// Current state of the notification loading lifecycle.
    @Published private(set) var state: TimelineState = .initialLoading
    /// Number of unread notifications.
    @Published private(set) var unreadCount = 0

    // MARK: - Private Properties

    /// Cursor for paginating through notifications.
    private var cursor: String?

    // MARK: - Public Methods

    /// Performs the initial load of notifications. Only fires when `state == .initialLoading`.
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

    /// Pull-to-refresh: reloads all notifications from scratch.
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

    /// Loads the next page of notifications.
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

    /// Marks all loaded notifications as read via the `updateSeen` API and updates local state.
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

    /// Fetches the current unread count from the server.
    func updateUnreadCount(account: AppAccount, appPassword: String, using client: LiveBlueskyClient) async {
        guard let count = try? await client.getUnreadCount(account: account, appPassword: appPassword) else { return }
        unreadCount = count
    }

    /// Resets all state to initial values (e.g. on account switch).
    func reset() {
        entries = []
        state = .initialLoading
        cursor = nil
        unreadCount = 0
    }

    // MARK: - Private Helpers

    /// Enriches `NotificationItem` array with related post data fetched in batch.
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

    /// Batch-fetches all posts referenced by the notification list.
    /// Falls back to individual fetches for any URIs that fail in the batch request.
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

        // Individually fetch any URIs that were missing from the batch result
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

    /// Extracts the relevant post URI from a notification based on its reason type.
    /// - Returns: The URI of the post to show as context, or `nil` for follows.
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
