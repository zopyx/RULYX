import Foundation
import Observation
import SwiftUI

/// View model for BlueskyProfileView's block-back and moderation action logic.
/// Extracted from the view body to enable isolated unit testing with mock services.
@MainActor
@Observable
final class BlueskyProfileActionsViewModel {
    // MARK: - Dependencies

    private var profileService: BlueskyProfileInspecting
    private var blocklistService: BlueskyBlocklistServicing
    private var accountStore: AccountStoreProtocol

    // MARK: - Block Counts

    var blockingCount: Int?
    var blockedByCount: Int?
    var unblockedBlockersCount: Int?
    /// True while the blocking count is being fetched.
    var isFetchingBlocking = false
    /// True while the blocked-by count is being fetched.
    var isFetchingBlockedBy = false
    /// True while the unblocked-blockers count is being fetched.
    var isFetchingUnblocked = false

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

    // MARK: - Recently-Blocked Tracking (PDS-level)

    /// Tracks DIDs we've blocked in the current session, so a refresh right after a
    /// block action already counts them instead of waiting for the repo cache to roll over.
    private var recentlyBlockedDIDs = Set<String>()

    // MARK: - Init

    /// Duration to display the result summary after block-back completes.
    /// Configurable for fast unit testing.
    var resultDisplayDuration: TimeInterval = 4.0

    init(
        profileService: BlueskyProfileInspecting,
        blocklistService: BlueskyBlocklistServicing,
        accountStore: AccountStoreProtocol
    ) {
        self.profileService = profileService
        self.blocklistService = blocklistService
        self.accountStore = accountStore
    }

    /// Reconfigure with new services for transition-period wiring.
    func reconfigure(
        profileService: BlueskyProfileInspecting,
        blocklistService: BlueskyBlocklistServicing,
        accountStore: AccountStoreProtocol
    ) {
        self.profileService = profileService
        self.blocklistService = blocklistService
        self.accountStore = accountStore
    }

    /// Convenience initializer using the live client (for transition period).
    convenience init(client: LiveBlueskyClient, accountStore: AccountStore) {
        self.init(
            profileService: client,
            blocklistService: client,
            accountStore: accountStore
        )
    }

    // MARK: - Block Counts

    /// Fetches all three block counts from one pair of blocklist reads
    /// (own repo + backlink index), then adjusts for recently-blocked DIDs
    /// that a cached response may not have picked up yet.
    func fetchBlockCounts(isOwnProfile: Bool) async {
        guard isOwnProfile else {
            resetBlockBackCounts()
            return
        }
        guard let account = accountStore.activeAccount else { return }

        // Clear numbers, show individual spinners
        blockingCount = nil
        isFetchingBlocking = true
        blockedByCount = nil
        isFetchingBlockedBy = true
        unblockedBlockersCount = nil
        isFetchingUnblocked = true

        // Fetch both sides in parallel (DIDs only – no profile resolution). Each side is
        // optional and independent — own repo vs. backlink index — so a failure on one
        // side must not blank out the other.
        async let blockedDIDsResult: Set<String>? = try? blocklistService.fetchBlockedDIDs(for: account)
        async let blockedByDIDsResult: Set<String>? = try? blocklistService.fetchBlockerDIDs(for: account)
        let (blocked, blockedBy) = await (blockedDIDsResult, blockedByDIDsResult)

        // Apply our recently-blocked supplement
        let effectiveBlocked = (blocked ?? []).union(recentlyBlockedDIDs)
        // The unblocked count is a set difference, so it only exists when both sides did.
        let unblockedCount = (blocked != nil && blockedBy != nil)
            ? max(0, blockedBy!.count - effectiveBlocked.count)
            : nil

        await MainActor.run {
            self.blockingCount = blocked?.count
            self.blockedByCount = blockedBy?.count
            self.unblockedBlockersCount = unblockedCount
            self.isFetchingBlocking = false
            self.isFetchingBlockedBy = false
            self.isFetchingUnblocked = false
        }
    }

    // MARK: - Block Back Preview

    var blockBackPreviewAvailable: Bool {
        guard let count = unblockedBlockersCount else { return false }
        return count > 0
    }

    func fetchBlockPreview() async {
        guard let account = accountStore.activeAccount else { return }
        let appPassword = accountStore.appPassword(for: account)
        isFetchingBlockPreview = true
        defer { isFetchingBlockPreview = false }

        do {
            blockPreviewActors = try await blocklistService.fetchUnblockedBlockerActors(
                account: account, appPassword: appPassword
            )
            showBlockBackPreview = true
        } catch {
            blockBackError = error.localizedDescription
        }
    }

    // MARK: - Block Back Execution

    func blockBack(actors: [BlueskyActor]? = nil) async {
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
                toBlock = try await blocklistService.fetchUnblockedBlockerActors(
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

        // P0: Pre-filter against PDS-level block records to avoid duplicates.
        // This is a real-time check against the PDS, not the cached list state.
        let existingBlockedDIDs: Set<String>
        do {
            existingBlockedDIDs = try await profileService.fetchExistingBlockedDIDs(
                account: account, appPassword: appPassword
            )
        } catch {
            // If the PDS query fails, use the blocklist data alone (no pre-filter)
            existingBlockedDIDs = []
            AppLogger.moderation.error("Failed to fetch existing blocked DIDs: \(error.localizedDescription, privacy: .public)")
        }

        let filteredToBlock = toBlock.filter { !existingBlockedDIDs.contains($0.did) }
        guard !filteredToBlock.isEmpty else {
            isBlockingBack = false
            return
        }

        blockBackTotal = filteredToBlock.count
        let batchSize = 5

        for batchStart in stride(from: 0, to: blockBackTotal, by: batchSize) {
            let batchEnd = min(batchStart + batchSize, blockBackTotal)
            let batch = filteredToBlock[batchStart ..< batchEnd]

            await withTaskGroup(of: (Bool, String).self) { group in
                for actor in batch {
                    group.addTask { [weak self] in
                        guard let self else { return (false, actor.handle) }
                        do {
                            try await profileService.blockActor(
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

        // Track successfully blocked DIDs to supplement the next refresh
        for actor in filteredToBlock {
            recentlyBlockedDIDs.insert(actor.did)
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
        isFetchingBlocking = false
        isFetchingBlockedBy = false
        isFetchingUnblocked = false
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
