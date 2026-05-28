import Foundation

/// A member of a list at the time a snapshot was captured.
struct SnapshotMember: Codable, Hashable {
    let did: String
    let handle: String
    let displayName: String?
}

/// A point-in-time capture of all members of a moderation list.
/// Used to detect membership changes (additions/removals) over time.
struct ListMembershipSnapshot: Codable, Hashable {
    let id: UUID
    /// The AT URI of the list.
    let listID: String
    /// The display name of the list at capture time.
    let listName: String
    /// When this snapshot was recorded.
    let capturedAt: Date
    /// The full member list at capture time.
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

/// The result of comparing two list membership snapshots.
struct ListMembershipSnapshotSummary: Hashable {
    let listID: String
    let listName: String
    let snapshotID: UUID
    let previousCaptureDate: Date?
    let currentCaptureDate: Date
    /// Members present in the new snapshot but absent from the previous one.
    let addedMembers: [SnapshotMember]
    /// Members present in the previous snapshot but absent from the new one.
    let removedMembers: [SnapshotMember]

    /// Whether any membership changes were detected.
    var hasChanges: Bool {
        !addedMembers.isEmpty || !removedMembers.isEmpty
    }
}

/// A log entry recording a completed moderation operation (e.g., bulk add/remove).
/// Stored in UserDefaults for persistence across app launches.
struct ModerationOperationLogEntry: Identifiable, Codable, Hashable {
    let id: UUID
    /// A summary title like "Bulk Add" or "Remove from List".
    let title: String
    /// Human-readable description (e.g., "3 accounts added, 1 failed.").
    let summary: String
    /// Handles that were successfully processed.
    let succeededHandles: [String]
    /// Handles that failed processing.
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

/// Manages list membership snapshots and moderation operation history.
/// Snapshots are used to detect membership drift across time.
/// All data is persisted to UserDefaults.
@MainActor
final class ModerationAuditStore: ObservableObject {
    /// The moderation operation log, newest first (capped at 25 entries).
    @Published private(set) var operationLog: [ModerationOperationLogEntry] = []

    private let defaults: UserDefaults
    private let snapshotsKey = "moderation.listSnapshots"
    private let operationLogKey = "moderation.operationLog"
    /// Maximum number of operation log entries to keep.
    private let operationLogLimit = 25
    /// Maximum number of snapshots per list.
    private let snapshotHistoryLimit = 12
    /// All snapshots, keyed by list ID.
    private var snapshotsByListID: [String: [ListMembershipSnapshot]] = [:]

    // MARK: - Init

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

    /// The most recent operation that had at least one success or failure. Used for undo.
    private(set) var lastUndoableOperation: ModerationOperationLogEntry?

    // MARK: - Public Methods

    /// Records a moderation operation in the log. Inserts at position 0 and caps at `operationLogLimit`.
    func recordOperation(_ result: ModerationOperationLogEntry) {
        if result.succeededHandles.count > 0 || result.failedHandles.count > 0 {
            lastUndoableOperation = result
        }
        operationLog.insert(result, at: 0)
        operationLog = Array(operationLog.prefix(operationLogLimit))
        AppLogger.persistence.debug("Recorded moderation operation '\(result.title, privacy: .public)' with \(result.succeededHandles.count) successes and \(result.failedHandles.count) failures.")
        persistOperationLog()
    }

    /// Clears the last undoable operation reference.
    func clearUndo() {
        lastUndoableOperation = nil
    }

    /// Captures a membership snapshot for a list and returns a summary of changes
    /// compared to the previous snapshot. Skips writing if membership is unchanged.
    func captureSnapshot(for list: BlueskyList, members: [BlueskyListMember]) -> ListMembershipSnapshotSummary {
        let currentMembers = members.map {
            SnapshotMember(
                did: $0.actor.did,
                handle: $0.actor.handle,
                displayName: $0.actor.displayName
            )
        }
        .sorted { $0.handle.localizedCaseInsensitiveCompare($1.handle) == .orderedAscending }

        // Compare against the most recent snapshot to detect deltas.
        let previousSnapshot = snapshotsByListID[list.id]?.sorted { $0.capturedAt > $1.capturedAt }.first
        let olderSnapshot = snapshotsByListID[list.id]?.sorted { $0.capturedAt > $1.capturedAt }.dropFirst().first
        let previousMembersByDID = Dictionary(uniqueKeysWithValues: (previousSnapshot?.members ?? []).map { ($0.did, $0) })
        let currentMembersByDID = Dictionary(uniqueKeysWithValues: currentMembers.map { ($0.did, $0) })

        // Members in current but not in previous → added.
        let added = currentMembersByDID.keys
            .filter { previousMembersByDID[$0] == nil }
            .compactMap { currentMembersByDID[$0] }
            .sorted { $0.handle.localizedCaseInsensitiveCompare($1.handle) == .orderedAscending }

        // Members in previous but not in current → removed.
        let removed = previousMembersByDID.keys
            .filter { currentMembersByDID[$0] == nil }
            .compactMap { previousMembersByDID[$0] }
            .sorted { $0.handle.localizedCaseInsensitiveCompare($1.handle) == .orderedAscending }

        // Skip writing a new snapshot if the membership is identical.
        if let previousSnapshot,
           previousSnapshot.members == currentMembers {
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

        // Persist the new snapshot.
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

    /// Returns the snapshot history for a given list, newest first.
    func snapshotHistory(for listID: String) -> [ListMembershipSnapshot] {
        (snapshotsByListID[listID] ?? []).sorted { $0.capturedAt > $1.capturedAt }
    }

    /// Compares two specific snapshots for a list and returns the diff.
    /// Returns `nil` if either snapshot ID is not found.
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

    // MARK: - Private Helpers

    /// Loads snapshots and operation log from UserDefaults.
    private func load() {
        if let data = defaults.data(forKey: snapshotsKey),
           let decoded = try? JSONDecoder().decode([String: [ListMembershipSnapshot]].self, from: data) {
            snapshotsByListID = decoded
        }

        if let data = defaults.data(forKey: operationLogKey),
           let decoded = try? JSONDecoder().decode([ModerationOperationLogEntry].self, from: data) {
            operationLog = decoded.sorted { $0.createdAt > $1.createdAt }
        }
    }

    /// Persists all snapshots to UserDefaults.
    private func persistSnapshots() {
        if let data = try? JSONEncoder().encode(snapshotsByListID) {
            defaults.set(data, forKey: snapshotsKey)
        }
    }

    /// Persists the operation log to UserDefaults.
    private func persistOperationLog() {
        if let data = try? JSONEncoder().encode(operationLog) {
            defaults.set(data, forKey: operationLogKey)
        }
    }
}
