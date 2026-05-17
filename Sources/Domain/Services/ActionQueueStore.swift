import Foundation

enum QueuedActionStatus: Equatable {
    case pending
    case running(Int, Int, String?)
    case completed(Int, Int)
}

struct QueuedAction: Identifiable {
    let id: UUID
    let title: String
    let createdAt: Date
    let actors: [BlueskyActor]
    let operation: ListBulkActionResult.Operation
    let action: @Sendable (BlueskyActor) async throws -> Void
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

@MainActor
final class ActionQueueStore: ObservableObject {
    @Published private(set) var actions: [QueuedAction] = []

    private var processingTask: Task<Void, Never>?

    func enqueue(_ action: QueuedAction) {
        actions.append(action)
        if processingTask == nil {
            processNext()
        }
    }

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

    func retry(_ id: UUID) {
        guard let idx = actions.firstIndex(where: { $0.id == id }),
              case .completed = actions[idx].status else { return }
        let action = actions[idx]
        actions.remove(at: idx)
        enqueue(action)
    }

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
                guard let self, let i = self.actions.firstIndex(where: { $0.id == actionID }) else { return }
                self.actions[i].status = .completed(result.succeededActors.count, result.failures.count)
                self.processingTask = nil
                self.processNext()
            }
        }
    }
}
