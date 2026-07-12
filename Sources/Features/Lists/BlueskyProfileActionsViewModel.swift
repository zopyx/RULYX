import Foundation
import SwiftUI
import Observation

/// View model for BlueskyProfileView's block-back and moderation action logic.
/// Extracted from the view body to enable isolated unit testing with mock services.
@MainActor
@Observable
final class BlueskyProfileActionsViewModel {
    // MARK: - Dependencies

    private var profileService: BlueskyProfileInspecting
    private var clearskyService: BlueskyClearSkyServicing
    private var accountStore: AccountStoreProtocol
    let clearskyHeartbeat: ClearskyHeartbeatService

    // MARK: - Block Counts

    var blockingCount: Int?
    var blockedByCount: Int?
    var unblockedBlockersCount: Int?
    var isFetchingBlockCounts = false

    // MARK: - Block Back State

    var isBlockingBack = false
    var blockBackCompleted = 0
    var blockBackTotal = 0
    var blockBackSuccessCount = 0
    var blockBackFailureCount = 0
    var blockBackError: String?
    var blockBackCurrentHandle: String?
    var showBlockBackResult = false

    // MARK: - Block Back Preview

    var showBlockBackPreview = false
    var blockPreviewActors: [BlueskyActor] = []
    var isFetchingBlockPreview = false

    // MARK: - Init

    /// Duration to display the result summary after block-back completes.
    /// Configurable for fast unit testing.
    var resultDisplayDuration: TimeInterval = 4.0

    init(
        profileService: BlueskyProfileInspecting,
        clearskyService: BlueskyClearSkyServicing,
        accountStore: AccountStoreProtocol,
        clearskyHeartbeat: ClearskyHeartbeatService = .shared
    ) {
        self.profileService = profileService
        self.clearskyService = clearskyService
        self.accountStore = accountStore
        self.clearskyHeartbeat = clearskyHeartbeat
    }

    /// Reconfigure with new services for transition-period wiring.
    func reconfigure(
        profileService: BlueskyProfileInspecting,
        clearskyService: BlueskyClearSkyServicing,
        accountStore: AccountStoreProtocol
    ) {
        self.profileService = profileService
        self.clearskyService = clearskyService
        self.accountStore = accountStore
    }

    /// Convenience initializer using the live client (for transition period).
    convenience init(client: LiveBlueskyClient, accountStore: AccountStore) {
        self.init(
            profileService: client,
            clearskyService: client,
            accountStore: accountStore
        )
    }

    // MARK: - Block Counts

    func fetchBlockCounts(isOwnProfile: Bool) async {
        guard isOwnProfile else {
            resetBlockBackCounts()
            return
        }
        guard let account = accountStore.activeAccount else { return }

        // Clear all numbers and show spinner
        blockingCount = nil
        blockedByCount = nil
        unblockedBlockersCount = nil
        isFetchingBlockCounts = true

        // Fetch all three in parallel
        async let blocking = clearskyService.fetchBlockingCount(for: account)
        async let blockedBy = clearskyService.fetchBlockedByCount(for: account)
        async let unblocked = clearskyService.fetchUnblockedBlockersCount(for: account)

        do {
            let (b, bb, ub) = try await (blocking, blockedBy, unblocked)
            blockingCount = b
            blockedByCount = bb
            unblockedBlockersCount = ub
        } catch {
            // Individual failures keep partial results as nil
            if let b = try? await blocking { blockingCount = b }
            if let bb = try? await blockedBy { blockedByCount = bb }
            if let ub = try? await unblocked { unblockedBlockersCount = ub }
        }

        isFetchingBlockCounts = false
    }

    // MARK: - Block Back Preview

    var blockBackPreviewAvailable: Bool {
        guard clearskyHeartbeat.isClearskyAvailable,
              let count = unblockedBlockersCount else { return false }
        return count > 0
    }

    func fetchBlockPreview() async {
        guard let account = accountStore.activeAccount else { return }
        let appPassword = accountStore.appPassword(for: account)
        isFetchingBlockPreview = true
        defer { isFetchingBlockPreview = false }

        do {
            blockPreviewActors = try await clearskyService.fetchUnblockedBlockerActors(
                account: account, appPassword: appPassword
            )
            showBlockBackPreview = true
        } catch {
            blockBackError = error.localizedDescription
        }
    }

    // MARK: - Block Back Execution

    func blockBack(actors: [BlueskyActor]? = nil) async {
        guard clearskyHeartbeat.isClearskyAvailable else { return }
        guard let account = accountStore.activeAccount else { return }

        // Password required only when fetching actors live; optional when pre-resolved
        let appPassword: String?
        if actors == nil {
            appPassword = accountStore.appPassword(for: account)
            guard appPassword != nil else { return }
        } else {
            appPassword = accountStore.appPassword(for: account) // try but don't require
        }

        isBlockingBack = true
        blockBackError = nil
        blockBackCompleted = 0
        blockBackTotal = 0
        blockBackSuccessCount = 0
        blockBackFailureCount = 0
        blockBackCurrentHandle = nil
        showBlockBackResult = false

        // Yield to let SwiftUI render the "preparing" spinner
        await Task.yield()

        let toBlock: [BlueskyActor]
        do {
            if let actors {
                toBlock = actors
            } else {
                toBlock = try await clearskyService.fetchUnblockedBlockerActors(
                    account: account, appPassword: appPassword
                )
            }
        } catch {
            blockBackError = error.localizedDescription
            isBlockingBack = false
            return
        }

        guard !toBlock.isEmpty else {
            isBlockingBack = false
            return
        }

        blockBackTotal = toBlock.count
        let batchSize = 5

        for batchStart in stride(from: 0, to: blockBackTotal, by: batchSize) {
            let batchEnd = min(batchStart + batchSize, blockBackTotal)
            let batch = toBlock[batchStart ..< batchEnd]

            await withTaskGroup(of: (Bool, String).self) { group in
                for actor in batch {
                    group.addTask { [weak self] in
                        guard let self else { return (false, actor.handle) }
                        do {
                            // Use profileService for blockActor (part of ProfileInspecting)
                            try await self.profileService.blockActor(
                                did: actor.did, account: account, appPassword: appPassword
                            )
                            return (true, actor.handle)
                        } catch {
                            return (false, actor.handle)
                        }
                    }
                }
                for await (success, handle) in group {
                    blockBackCurrentHandle = handle
                    blockBackCompleted += 1
                    if success {
                        blockBackSuccessCount += 1
                    } else {
                        blockBackFailureCount += 1
                    }
                }
            }

            if batchEnd < blockBackTotal {
                try? await Task.sleep(for: .milliseconds(300))
            }
        }

        showBlockBackResult = true
        blockBackCurrentHandle = nil
        await fetchBlockCounts(isOwnProfile: true)

        try? await Task.sleep(for: .seconds(resultDisplayDuration))
        showBlockBackResult = false
        isBlockingBack = false
    }

    // MARK: - Helpers

    func resetBlockBackCounts() {
        blockingCount = nil
        blockedByCount = nil
        unblockedBlockersCount = nil
        isFetchingBlockCounts = false
        isFetchingBlockPreview = false
        showBlockBackPreview = false
        blockPreviewActors = []
        blockBackCurrentHandle = nil
    }

    var blockBackResultSummary: String {
        if blockBackFailureCount == 0 {
            return loc("profile.block_back.result_success")
                .replacingOccurrences(of: "{count}", with: "\(blockBackSuccessCount)")
        }
        return loc("profile.block_back.result")
            .replacingOccurrences(of: "{success}", with: "\(blockBackSuccessCount)")
            .replacingOccurrences(of: "{fail}", with: "\(blockBackFailureCount)")
    }

    static func countText(_ value: Int?) -> String {
        if let value {
            return "\(value)"
        }
        return "-"
    }
}
