import Foundation

// MARK: - ListBatchController

/// Executes bulk moderation actions (add, remove, block, mute, etc.) on
/// lists of actors with batching, retry, progress callbacks, and cancellation support.
@MainActor
final class ListBatchController {
    private let baseDelay: UInt64
    private let batchSize = 5

    /// - Parameter baseDelay: Nanoseconds to wait between batches and retries.
    init(baseDelay: UInt64 = 300_000_000) {
        self.baseDelay = baseDelay
    }

    /// Performs a batch action across all actors with retry (3 attempts per actor).
    /// - Parameters:
    ///   - actors: Actors to process.
    ///   - operation: Label for the result summary.
    ///   - onProgress: Called after each actor completes.
    ///   - onActorComplete: Called immediately after each actor finishes.
    ///   - isCancelled: Closure checked between batches.
    ///   - action: The async action to perform on each actor.
    func performBatch(
        title: String,
        actors: [BlueskyActor],
        operation: ListBulkActionResult.Operation,
        onProgress: ((BatchProgress) -> Void)? = nil,
        onActorComplete: ((BlueskyActor) -> Void)? = nil,
        isCancelled: @escaping () -> Bool = { false },
        action: @escaping (BlueskyActor) async throws -> Void
    ) async -> ListBulkActionResult {
        var succeededActors: [BlueskyActor] = []
        var failures: [ListBulkActionResult.Failure] = []
        var completedCount = 0

        let totalCount = actors.count
        var batchStart = 0
        let actionBox = ActionBox(action: action)

        while batchStart < totalCount {
            guard !Task.isCancelled, !isCancelled() else { break }

            let batchEnd = min(batchStart + batchSize, totalCount)
            let batch = Array(actors[batchStart ..< batchEnd])

            let results = await withTaskGroup(
                of: (BlueskyActor, String?).self,
                returning: [(BlueskyActor, String?)].self
            ) { group in
                for actor in batch {
                    group.addTask { [baseDelay] in
                        var lastError: String?
                        for attempt in 0 ..< 3 {
                            guard !Task.isCancelled else { break }
                            do {
                                try await actionBox.action(actor)
                                lastError = nil
                                break
                            } catch {
                                lastError = error.localizedDescription
                                if attempt < 2 {
                                    try? await Task.sleep(for: .nanoseconds(baseDelay))
                                }
                            }
                        }
                        return (actor, lastError)
                    }
                }
                var collected: [(BlueskyActor, String?)] = []
                for await result in group {
                    collected.append(result)
                }
                return collected
            }

            for (actor, errorMessage) in results {
                onActorComplete?(actor)
                completedCount += 1
                onProgress?(
                    BatchProgress(
                        title: title,
                        completedCount: completedCount,
                        totalCount: totalCount,
                        currentHandle: actor.handle
                    )
                )
                if let errorMessage {
                    failures.append(.init(actor: actor, message: errorMessage))
                } else {
                    succeededActors.append(actor)
                }
            }

            batchStart += batchSize

            if batchStart < totalCount {
                try? await Task.sleep(for: .nanoseconds(baseDelay))
            }
        }

        return ListBulkActionResult(
            operation: operation,
            succeededActors: succeededActors,
            failures: failures
        )
    }
}

/// Wraps a Sendable closure for use with TaskGroup.
private struct ActionBox: @unchecked Sendable {
    let action: (BlueskyActor) async throws -> Void
}
