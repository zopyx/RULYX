import Foundation

/// Moderation report operations.
@MainActor
protocol BlueskyModerationServicing: Sendable {
    /// Report a list with free-form reason.
    func reportList(
        _ list: BlueskyList,
        reason: String?,
        account: AppAccount,
        appPassword: String?
    ) async throws

    /// Report a list with a selectable reason type.
    func reportList(
        _ list: BlueskyList,
        selectedReason: ModerationReportReasonType?,
        reason: String?,
        account: AppAccount,
        appPassword: String?
    ) async throws

    /// Report a record (post) by URI and CID.
    func reportRecord(
        uri: String,
        cid: String,
        reason: String?,
        selectedReason: ModerationReportReasonType?,
        account: AppAccount,
        appPassword: String?
    ) async throws
}
