import Foundation

/// Tracks the execution state of a queued bulk action.
enum QueuedActionStatus: Equatable {
    /// Waiting to be processed.
    case pending
    /// Currently executing. Associated values: (completedCount, totalCount, currentHandle).
    case running(Int, Int, String?)
    /// Finished execution. Associated values: (succeededCount, failedCount).
    case completed(Int, Int)
}

/// A bulk action queued for asynchronous processing against a list of actors.
struct QueuedAction: Identifiable {
    let id: UUID
    /// A human-readable title shown in the UI (e.g., "Add to Mod List").
    let title: String
    /// When this action was enqueued.
    let createdAt: Date
    /// The actors this action will be applied to.
    let actors: [BlueskyActor]
    /// The type of operation for result tracking.
    let operation: ListBulkActionResult.Operation
    /// The closure that performs the action for a single actor.
    let action: @Sendable (BlueskyActor) async throws -> Void
    /// The current execution status.
    var status: QueuedActionStatus

    init(
        id: UUID = UUID(),
        title: String,
        actors: [BlueskyActor],
        operation: ListBulkActionResult.Operation,
        action: @escaping @Sendable (BlueskyActor) async throws -> Void
    ) {
        self.id = id
        self.title = title
        createdAt = .now
        self.actors = actors
        self.operation = operation
        self.action = action
        status = .pending
    }
}

extension QueuedAction: Hashable {
    static func == (lhs: QueuedAction, rhs: QueuedAction) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

/// A serial action queue that processes one bulk action at a time.
/// Each action is a closure applied to an array of actors sequentially.
/// The queue automatically processes the next pending action when the current one completes.
@MainActor
final class ActionQueueStore: ObservableObject {
    /// All queued actions. The first pending action is processed automatically.
    @Published private(set) var actions: [QueuedAction] = []

    /// The currently executing processing task (nil when idle).
    private var processingTask: Task<Void, Never>?

    // MARK: - Public Methods

    /// Adds an action to the queue and starts processing if idle.
    func enqueue(_ action: QueuedAction) {
        actions.append(action)
        if processingTask == nil {
            processNext()
        }
    }

    /// Cancels and removes an action from the queue.
    /// If the action is currently running, the processing task is cancelled.
    func cancel(_ id: UUID) {
        if let idx = actions.firstIndex(where: { $0.id == id }) {
            if case .running = actions[idx].status {
                processingTask?.cancel()
                processingTask = nil
            }
            actions.remove(at: idx)
        }
        if processingTask == nil {
            processNext()
        }
    }

    /// Re-queues a completed action by removing it and enqueuing a fresh copy.
    func retry(_ id: UUID) {
        guard let idx = actions.firstIndex(where: { $0.id == id }),
              case .completed = actions[idx].status else { return }
        let action = actions[idx]
        actions.remove(at: idx)
        enqueue(action)
    }

    // MARK: - Private Helpers

    /// Finds the next pending action and starts processing it via `ListBatchController`.
    private func processNext() {
        guard processingTask == nil else { return }
        guard let idx = actions.firstIndex(where: { if case .pending = $0.status { true } else { false } }) else { return }

        let action = actions[idx]
        let actionID = action.id
        actions[idx].status = .running(0, action.actors.count, nil)

        processingTask = Task { [weak self] in
            let batchController = ListBatchController()
            let result = await batchController.performBatch(
                title: action.title,
                actors: action.actors,
                operation: action.operation,
                onProgress: { progress in
                    Task { @MainActor in
                        guard let self, let i = self.actions.firstIndex(where: { $0.id == actionID }) else { return }
                        self.actions[i].status = .running(progress.completedCount, progress.totalCount, progress.currentHandle)
                    }
                },
                onActorComplete: nil,
                action: action.action
            )

            await MainActor.run { [weak self] in
                guard let self, let i = actions.firstIndex(where: { $0.id == actionID }) else { return }
                actions[i].status = .completed(result.succeededActors.count, result.failures.count)
                processingTask = nil
                processNext()
            }
        }
    }
}
