import Foundation

/// Protocol for account state access used by view models.
/// Extracted from AccountStore to enable mock testing.
@MainActor
protocol AccountStoreProtocol: AnyObject {
    var activeAccount: AppAccount? { get }
    func appPassword(for account: AppAccount) -> String?
}
