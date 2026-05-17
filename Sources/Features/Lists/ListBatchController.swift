import Foundation

@MainActor
final class ListBatchController {
    private let baseDelay: UInt64
    private let batchSize = 5

    init(baseDelay: UInt64 = 300_000_000) {
        self.baseDelay = baseDelay
    }

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

private struct ActionBox: @unchecked Sendable {
    let action: (BlueskyActor) async throws -> Void
}
