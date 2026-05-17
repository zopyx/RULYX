import Foundation

@MainActor
final class ListBatchProgressState: ObservableObject, @unchecked Sendable {
    @Published var isPerformingBulkAction = false
    @Published var batchProgress: BatchProgress?
    @Published var addingActorIDs: Set<String> = []
    @Published var removingMemberIDs: Set<String> = []

    private(set) var isBatchCancelled = false

    func cancelBatch() {
        isBatchCancelled = true
        isPerformingBulkAction = false
    }

    func resetBatchCancellation() {
        isBatchCancelled = false
    }

    func isAdding(_ actor: BlueskyActor) -> Bool {
        addingActorIDs.contains(actor.did)
    }

    func isRemoving(_ member: BlueskyListMember) -> Bool {
        removingMemberIDs.contains(member.id)
    }
}
