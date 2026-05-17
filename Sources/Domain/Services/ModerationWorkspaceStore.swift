import Combine
import Foundation

@MainActor
final class ModerationWorkspaceStore: ObservableObject {
    @Published private(set) var savedSearches: [SavedProfileSearch] = []
    @Published private(set) var recentSearches: [RecentProfileSearch] = []
    @Published private(set) var operationLog: [ModerationOperationLogEntry] = []
    @Published var selectedTab: WorkspaceTab = .moderation {
        didSet {
            guard selectedTab != oldValue else { return }
            preferencesStore.selectedTab = selectedTab
        }
    }
    @Published private(set) var moderationNavigationResetToken = UUID()
    @Published var pendingChatConversation: ChatConversation?
    @Published var pendingChatConversationID: String?
    @Published var lastProfileQuery = ""
    @Published private(set) var queuedActions: [QueuedAction] = []

    let actionQueue = ActionQueueStore()

    private let preferencesStore: WorkspacePreferencesStore
    private let auditStore: ModerationAuditStore

    init(defaults: UserDefaults = .standard, preview: Bool = false) {
        preferencesStore = WorkspacePreferencesStore(defaults: defaults, preview: preview)
        auditStore = ModerationAuditStore(defaults: defaults, preview: preview)
        selectedTab = preferencesStore.selectedTab
        syncFromStores()
        setupBindings()
        setupActionQueueBindings()
    }

    func returnToModerationRoot() {
        selectedTab = .moderation
        moderationNavigationResetToken = UUID()
    }

    func saveProfileSearch(_ query: String) {
        preferencesStore.saveProfileSearch(query)
        syncFromPreferences()
    }

    func deleteSavedSearch(_ search: SavedProfileSearch) {
        preferencesStore.deleteSavedSearch(search)
        syncFromPreferences()
    }

    func noteRecentSearch(_ query: String) {
        preferencesStore.noteRecentSearch(query)
        syncFromPreferences()
    }

    func recordOperation(_ result: ModerationOperationLogEntry) {
        auditStore.recordOperation(result)
        syncFromAudit()
    }

    func captureSnapshot(for list: BlueskyList, members: [BlueskyListMember]) -> ListMembershipSnapshotSummary {
        let summary = auditStore.captureSnapshot(for: list, members: members)
        syncFromAudit()
        return summary
    }

    func snapshotHistory(for listID: String) -> [ListMembershipSnapshot] {
        auditStore.snapshotHistory(for: listID)
    }

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

    private func setupBindings() {
        preferencesStore.objectWillChange.sink { [weak self] in
            self?.syncFromPreferences()
        }.store(in: &cancellables)

        auditStore.objectWillChange.sink { [weak self] in
            self?.syncFromAudit()
        }.store(in: &cancellables)
    }

    private func syncFromStores() {
        syncFromPreferences()
        syncFromAudit()
        syncFromActionQueue()
    }

    private func syncFromPreferences() {
        savedSearches = preferencesStore.savedSearches
        recentSearches = preferencesStore.recentSearches
        lastProfileQuery = preferencesStore.lastProfileQuery
    }

    private func syncFromAudit() {
        operationLog = auditStore.operationLog
    }

    private func syncFromActionQueue() {
        queuedActions = actionQueue.actions
    }

    private func setupActionQueueBindings() {
        actionQueue.objectWillChange.sink { [weak self] in
            self?.syncFromActionQueue()
        }.store(in: &cancellables)
    }

    private var cancellables: Set<AnyCancellable> = []
}
