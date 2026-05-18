import Foundation

@MainActor
final class NotificationViewModel: ObservableObject {
    @Published private(set) var entries: [NotificationItem] = []
    @Published private(set) var state: TimelineState = .initialLoading
    @Published private(set) var unreadCount = 0

    private var cursor: String?

    func load(account: AppAccount, appPassword: String, using client: LiveBlueskyClient) async {
        guard state == .initialLoading else { return }
        do {
            let response = try await client.fetchNotifications(cursor: nil, account: account, appPassword: appPassword)
            entries = response.notifications
            cursor = response.cursor
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
            entries = response.notifications
            cursor = response.cursor
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
            entries += response.notifications
            self.cursor = response.cursor
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
                entries[i].isRead = true
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
}
