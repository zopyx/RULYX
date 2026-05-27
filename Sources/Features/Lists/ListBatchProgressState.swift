import Foundation

// MARK: - ListBatchProgressState

/// Observable state for tracking batch operation progress and cancellation.
@MainActor
final class ListBatchProgressState: ObservableObject, @unchecked Sendable {
    @Published var isPerformingBulkAction = false
    @Published var batchProgress: BatchProgress?
    @Published var addingActorIDs: Set<String> = []
    @Published var removingMemberIDs: Set<String> = []

    private(set) var isBatchCancelled = false

    /// Marks the batch as cancelled and resets the performing flag.
    func cancelBatch() {
        isBatchCancelled = true
        isPerformingBulkAction = false
    }

    /// Clears the cancellation flag before starting a new batch.
    func resetBatchCancellation() {
        isBatchCancelled = false
    }

    /// Whether this actor is currently being added.
    func isAdding(_ actor: BlueskyActor) -> Bool {
        addingActorIDs.contains(actor.did)
    }

    /// Whether this member is currently being removed.
    func isRemoving(_ member: BlueskyListMember) -> Bool {
        removingMemberIDs.contains(member.id)
    }
}
