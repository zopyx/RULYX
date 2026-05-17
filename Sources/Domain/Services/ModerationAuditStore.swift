import Foundation

struct SnapshotMember: Codable, Hashable {
    let did: String
    let handle: String
    let displayName: String?
}

struct ListMembershipSnapshot: Codable, Hashable {
    let id: UUID
    let listID: String
    let listName: String
    let capturedAt: Date
    let members: [SnapshotMember]

    init(
        id: UUID = UUID(),
        listID: String,
        listName: String,
        capturedAt: Date,
        members: [SnapshotMember]
    ) {
        self.id = id
        self.listID = listID
        self.listName = listName
        self.capturedAt = capturedAt
        self.members = members
    }
}

struct ListMembershipSnapshotSummary: Hashable {
    let listID: String
    let listName: String
    let snapshotID: UUID
    let previousCaptureDate: Date?
    let currentCaptureDate: Date
    let addedMembers: [SnapshotMember]
    let removedMembers: [SnapshotMember]

    var hasChanges: Bool {
        !addedMembers.isEmpty || !removedMembers.isEmpty
    }
}

struct ModerationOperationLogEntry: Identifiable, Codable, Hashable {
    let id: UUID
    let title: String
    let summary: String
    let succeededHandles: [String]
    let failedHandles: [String]
    let createdAt: Date

    init(
        id: UUID = UUID(),
        title: String,
        summary: String,
        succeededHandles: [String],
        failedHandles: [String],
        createdAt: Date = .now
    ) {
        self.id = id
        self.title = title
        self.summary = summary
        self.succeededHandles = succeededHandles
        self.failedHandles = failedHandles
        self.createdAt = createdAt
    }
}

@MainActor
final class ModerationAuditStore: ObservableObject {
    @Published private(set) var operationLog: [ModerationOperationLogEntry] = []

    private let defaults: UserDefaults
    private let snapshotsKey = "moderation.listSnapshots"
    private let operationLogKey = "moderation.operationLog"
    private let operationLogLimit = 25
    private let snapshotHistoryLimit = 12
    private var snapshotsByListID: [String: [ListMembershipSnapshot]] = [:]

    init(defaults: UserDefaults = .standard, preview: Bool = false) {
        self.defaults = defaults

        if preview {
            operationLog = [
                ModerationOperationLogEntry(
                    title: "Bulk Add",
                    summary: "3 accounts added, 1 failed.",
                    succeededHandles: ["alice.bsky.social", "moderator.bsky.social", "safetylab.bsky.social"],
                    failedHandles: ["broken-handle"]
                ),
            ]
            return
        }

        load()
    }

    private(set) var lastUndoableOperation: ModerationOperationLogEntry?

    func recordOperation(_ result: ModerationOperationLogEntry) {
        if result.succeededHandles.count > 0 || result.failedHandles.count > 0 {
            lastUndoableOperation = result
        }
        operationLog.insert(result, at: 0)
        operationLog = Array(operationLog.prefix(operationLogLimit))
        AppLogger.persistence.debug("Recorded moderation operation '\(result.title, privacy: .public)' with \(result.succeededHandles.count) successes and \(result.failedHandles.count) failures.")
        persistOperationLog()
    }

    func clearUndo() {
        lastUndoableOperation = nil
    }

    func captureSnapshot(for list: BlueskyList, members: [BlueskyListMember]) -> ListMembershipSnapshotSummary {
        let currentMembers = members.map {
            SnapshotMember(
                did: $0.actor.did,
                handle: $0.actor.handle,
                displayName: $0.actor.displayName
            )
        }
        .sorted { $0.handle.localizedCaseInsensitiveCompare($1.handle) == .orderedAscending }

        let previousSnapshot = snapshotsByListID[list.id]?.sorted { $0.capturedAt > $1.capturedAt }.first
        let olderSnapshot = snapshotsByListID[list.id]?.sorted { $0.capturedAt > $1.capturedAt }.dropFirst().first
        let previousMembersByDID = Dictionary(uniqueKeysWithValues: (previousSnapshot?.members ?? []).map { ($0.did, $0) })
        let currentMembersByDID = Dictionary(uniqueKeysWithValues: currentMembers.map { ($0.did, $0) })

        let added = currentMembersByDID.keys
            .filter { previousMembersByDID[$0] == nil }
            .compactMap { currentMembersByDID[$0] }
            .sorted { $0.handle.localizedCaseInsensitiveCompare($1.handle) == .orderedAscending }

        let removed = previousMembersByDID.keys
            .filter { currentMembersByDID[$0] == nil }
            .compactMap { previousMembersByDID[$0] }
            .sorted { $0.handle.localizedCaseInsensitiveCompare($1.handle) == .orderedAscending }

        if let previousSnapshot,
           previousSnapshot.members == currentMembers
        {
            AppLogger.persistence.debug("Skipped snapshot write for list '\(list.name, privacy: .public)' because membership was unchanged.")
            return ListMembershipSnapshotSummary(
                listID: list.id,
                listName: list.name,
                snapshotID: previousSnapshot.id,
                previousCaptureDate: olderSnapshot?.capturedAt,
                currentCaptureDate: previousSnapshot.capturedAt,
                addedMembers: [],
                removedMembers: []
            )
        }

        let snapshot = ListMembershipSnapshot(
            listID: list.id,
            listName: list.name,
            capturedAt: .now,
            members: currentMembers
        )
        var history = snapshotsByListID[list.id] ?? []
        history.insert(snapshot, at: 0)
        history = Array(history.prefix(snapshotHistoryLimit))
        snapshotsByListID[list.id] = history
        AppLogger.persistence.debug("Captured snapshot for list '\(list.name, privacy: .public)' with \(currentMembers.count) members.")
        persistSnapshots()

        return ListMembershipSnapshotSummary(
            listID: list.id,
            listName: list.name,
            snapshotID: snapshot.id,
            previousCaptureDate: previousSnapshot?.capturedAt,
            currentCaptureDate: snapshot.capturedAt,
            addedMembers: added,
            removedMembers: removed
        )
    }

    func snapshotHistory(for listID: String) -> [ListMembershipSnapshot] {
        (snapshotsByListID[listID] ?? []).sorted { $0.capturedAt > $1.capturedAt }
    }

    func compareSnapshots(
        listID: String,
        newerSnapshotID: UUID,
        olderSnapshotID: UUID
    ) -> ListMembershipSnapshotSummary? {
        let history = snapshotsByListID[listID] ?? []
        guard let newer = history.first(where: { $0.id == newerSnapshotID }),
              let older = history.first(where: { $0.id == olderSnapshotID })
        else {
            return nil
        }

        let olderByDID = Dictionary(uniqueKeysWithValues: older.members.map { ($0.did, $0) })
        let newerByDID = Dictionary(uniqueKeysWithValues: newer.members.map { ($0.did, $0) })

        let added = newerByDID.keys
            .filter { olderByDID[$0] == nil }
            .compactMap { newerByDID[$0] }
            .sorted { $0.handle.localizedCaseInsensitiveCompare($1.handle) == .orderedAscending }

        let removed = olderByDID.keys
            .filter { newerByDID[$0] == nil }
            .compactMap { olderByDID[$0] }
            .sorted { $0.handle.localizedCaseInsensitiveCompare($1.handle) == .orderedAscending }

        return ListMembershipSnapshotSummary(
            listID: listID,
            listName: newer.listName,
            snapshotID: newer.id,
            previousCaptureDate: older.capturedAt,
            currentCaptureDate: newer.capturedAt,
            addedMembers: added,
            removedMembers: removed
        )
    }

    private func load() {
        if let data = defaults.data(forKey: snapshotsKey),
           let decoded = try? JSONDecoder().decode([String: [ListMembershipSnapshot]].self, from: data)
        {
            snapshotsByListID = decoded
        }

        if let data = defaults.data(forKey: operationLogKey),
           let decoded = try? JSONDecoder().decode([ModerationOperationLogEntry].self, from: data)
        {
            operationLog = decoded.sorted { $0.createdAt > $1.createdAt }
        }
    }

    private func persistSnapshots() {
        if let data = try? JSONEncoder().encode(snapshotsByListID) {
            defaults.set(data, forKey: snapshotsKey)
        }
    }

    private func persistOperationLog() {
        if let data = try? JSONEncoder().encode(operationLog) {
            defaults.set(data, forKey: operationLogKey)
        }
    }
}
