import Foundation

/// Notification operations.
@MainActor
protocol BlueskyNotificationServicing: Sendable {
    /// Fetch paginated notifications.
    func fetchNotifications(
        cursor: String?,
        limit: Int,
        account: AppAccount,
        appPassword: String?
    ) async throws -> ListNotificationsResponse

    /// Get the unread notification count.
    func getUnreadCount(
        account: AppAccount,
        appPassword: String?
    ) async throws -> Int

    /// Mark notifications as seen up to the given date.
    func updateSeen(
        at date: Date,
        account: AppAccount,
        appPassword: String?
    ) async throws
}
