import Combine
import Foundation

/// The central coordinator for the moderation workspace. Owns and syncs state from
/// `WorkspacePreferencesStore`, `ModerationAuditStore`, and `ActionQueueStore`.
/// Provides a single point of interaction for the moderation UI.
@MainActor
final class ModerationWorkspaceStore: ObservableObject {
    /// Saved profile searches sourced from `WorkspacePreferencesStore`.
    @Published private(set) var savedSearches: [SavedProfileSearch] = []
    /// Recent profile searches sourced from `WorkspacePreferencesStore`.
    @Published private(set) var recentSearches: [RecentProfileSearch] = []
    /// The operation log sourced from `ModerationAuditStore`.
    @Published private(set) var operationLog: [ModerationOperationLogEntry] = []
    /// The currently selected workspace tab. Changes propagate to `WorkspacePreferencesStore`.
    @Published var selectedTab: WorkspaceTab = .moderation {
        didSet {
            guard selectedTab != oldValue else { return }
            preferencesStore.selectedTab = selectedTab
        }
    }

    /// Incremented each time the moderation navigation stack should pop to root.
    @Published private(set) var moderationNavigationResetToken = UUID()
    /// A pending chat conversation to navigate to (set from moderation context).
    @Published var pendingChatConversation: ChatConversation?
    /// The ID of a pending chat conversation to navigate to.
    @Published var pendingChatConversationID: String?
    /// The last profile query entered by the user.
    @Published var lastProfileQuery = ""
    /// Queued bulk actions sourced from `ActionQueueStore`.
    @Published private(set) var queuedActions: [QueuedAction] = []

    /// The action queue for serialized bulk moderation operations.
    let actionQueue = ActionQueueStore()

    private let preferencesStore: WorkspacePreferencesStore
    private let auditStore: ModerationAuditStore

    // MARK: - Init

    init(defaults: UserDefaults = .standard, preview: Bool = false) {
        preferencesStore = WorkspacePreferencesStore(defaults: defaults, preview: preview)
        auditStore = ModerationAuditStore(defaults: defaults, preview: preview)
        selectedTab = preferencesStore.selectedTab
        syncFromStores()
        setupBindings()
        setupActionQueueBindings()
    }

    // MARK: - Public Methods

    /// Resets the moderation tab to its root state and generates a new navigation token.
    func returnToModerationRoot() {
        selectedTab = .moderation
        moderationNavigationResetToken = UUID()
    }

    /// Saves a profile search query through the preferences store.
    func saveProfileSearch(_ query: String) {
        preferencesStore.saveProfileSearch(query)
        syncFromPreferences()
    }

    /// Deletes a saved profile search through the preferences store.
    func deleteSavedSearch(_ search: SavedProfileSearch) {
        preferencesStore.deleteSavedSearch(search)
        syncFromPreferences()
    }

    /// Records a recent search query through the preferences store.
    func noteRecentSearch(_ query: String) {
        preferencesStore.noteRecentSearch(query)
        syncFromPreferences()
    }

    /// Records a moderation operation in the audit store.
    func recordOperation(_ result: ModerationOperationLogEntry) {
        auditStore.recordOperation(result)
        syncFromAudit()
    }

    /// Captures a membership snapshot and returns a diff summary against the previous snapshot.
    func captureSnapshot(for list: BlueskyList, members: [BlueskyListMember]) -> ListMembershipSnapshotSummary {
        let summary = auditStore.captureSnapshot(for: list, members: members)
        syncFromAudit()
        return summary
    }

    /// Returns the snapshot history for a list.
    func snapshotHistory(for listID: String) -> [ListMembershipSnapshot] {
        auditStore.snapshotHistory(for: listID)
    }

    /// Compares two specific snapshots for a list.
    func compareSnapshots(
        listID: String,
        newerSnapshotID: UUID,
        olderSnapshotID: UUID
    ) -> ListMembershipSnapshotSummary? {
        auditStore.compareSnapshots(
            listID: listID,
            newerSnapshotID: newerSnapshotID,
            olderSnapshotID: olderSnapshotID
        )
    }

    // MARK: - Private Helpers

    /// Subscribes to changes from sub-stores to keep published properties in sync.
    private func setupBindings() {
        preferencesStore.objectWillChange.sink { [weak self] in
            self?.syncFromPreferences()
        }.store(in: &cancellables)

        auditStore.objectWillChange.sink { [weak self] in
            self?.syncFromAudit()
        }.store(in: &cancellables)
    }

    /// Initial sync from all sub-stores on init.
    private func syncFromStores() {
        syncFromPreferences()
        syncFromAudit()
        syncFromActionQueue()
    }

    /// Syncs published properties from `WorkspacePreferencesStore`.
    private func syncFromPreferences() {
        savedSearches = preferencesStore.savedSearches
        recentSearches = preferencesStore.recentSearches
        lastProfileQuery = preferencesStore.lastProfileQuery
    }

    /// Syncs published properties from `ModerationAuditStore`.
    private func syncFromAudit() {
        operationLog = auditStore.operationLog
    }

    /// Syncs published properties from `ActionQueueStore`.
    private func syncFromActionQueue() {
        queuedActions = actionQueue.actions
    }

    /// Subscribes to `ActionQueueStore` changes.
    private func setupActionQueueBindings() {
        actionQueue.objectWillChange.sink { [weak self] in
            self?.syncFromActionQueue()
        }.store(in: &cancellables)
    }

    private var cancellables: Set<AnyCancellable> = []
}
