import BackgroundTasks
import UserNotifications
import SwiftUI

// MARK: - AutoBlockBackService

/// Periodically checks for accounts that block the user but aren't blocked back,
/// and automatically blocks them. Optionally also adds them to configured
/// moderation/curation/internal lists.
///
/// Triggered on app foreground and via `BGAppRefreshTask` (best-effort background).
///
/// Controlled by:
/// - `@AppStorage("autoBlockBackEnabled")` (default: `true`)
/// - `@AppStorage("autoBlockTargetListIDs")` — JSON-encoded `[String]` of list IDs
@MainActor
final class AutoBlockBackService: ObservableObject {
    // MARK: - Constants

    private static let taskIdentifier = "com.ajung.RULYX.autoblockback"

    // MARK: - Properties

    @AppStorage("autoBlockBackEnabled") var isEnabled = true
    @AppStorage("autoBlockTargetListIDs") private var targetListIDsData = Data()

    @Published private(set) var isRunning = false
    @Published private(set) var lastResult: Result?

    private weak var blueskyClient: LiveBlueskyClient?
    private weak var accountStore: AccountStore?
    private weak var internalListStore: InternalListStore?

    // MARK: - Result

    struct Result {
        let blockedCount: Int
        let failedCount: Int
        let addedToListCount: Int
        let listNames: [String]
        let timestamp: Date
    }

    // MARK: - Init

    init(
        blueskyClient: LiveBlueskyClient,
        accountStore: AccountStore,
        internalListStore: InternalListStore
    ) {
        self.blueskyClient = blueskyClient
        self.accountStore = accountStore
        self.internalListStore = internalListStore
        registerBGTask()
    }

    // MARK: - Public API

    /// Performs the auto-block-back check and operation. Safe to call from
    /// foreground or background. Posts a local notification with the count
    /// of newly blocked accounts and list additions.
    func performAutoBlockBack() async {
        guard isEnabled else { return }
        guard !isRunning else { return }
        guard let client = blueskyClient,
              let account = accountStore?.activeAccount,
              let appPassword = accountStore?.appPassword(for: account) else { return }

        isRunning = true
        defer { isRunning = false }

        do {
            let toBlock = try await client.fetchUnblockedBlockerActors(
                account: account,
                appPassword: appPassword
            )
            guard !toBlock.isEmpty else {
                lastResult = Result(
                    blockedCount: 0, failedCount: 0,
                    addedToListCount: 0, listNames: [],
                    timestamp: .now
                )
                return
            }

            // Load target lists from UserDefaults
            let targetLists = await loadTargetLists(
                account: account,
                appPassword: appPassword,
                using: client
            )

            var blocked = 0
            var failed = 0

            for actor in toBlock {
                do {
                    try await client.blockActor(
                        did: actor.did,
                        account: account,
                        appPassword: appPassword
                    )
                    blocked += 1

                    // Add to configured lists
                    for list in targetLists {
                        try? await addActorToTargetList(
                            did: actor.did,
                            handle: actor.handle,
                            list: list,
                            account: account,
                            appPassword: appPassword,
                            using: client
                        )
                    }
                } catch {
                    failed += 1
                    AppLogger.moderation.error(
                        "Auto-block-back failed for \(actor.handle, privacy: .public): \(error.localizedDescription, privacy: .public)"
                    )
                }
            }

            let listNames = targetLists.map(\.name)
            lastResult = Result(
                blockedCount: blocked,
                failedCount: failed,
                addedToListCount: targetLists.isEmpty ? 0 : blocked,
                listNames: listNames,
                timestamp: .now
            )

            if blocked > 0 {
                await sendNotification(
                    blockedCount: blocked,
                    failedCount: failed,
                    listNames: listNames
                )
            }
        } catch {
            AppLogger.moderation.error(
                "Auto-block-back fetch failed: \(error.localizedDescription, privacy: .public)"
            )
        }
    }

    /// Schedules the next `BGAppRefreshTask`. Call when the app enters background.
    func scheduleBackgroundTask() {
        guard isEnabled else { return }
        let request = BGAppRefreshTaskRequest(identifier: Self.taskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 5 * 60) // 5 minutes
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            AppLogger.moderation.error(
                "Failed to schedule auto-block-back BGTask: \(error.localizedDescription, privacy: .public)"
            )
        }
    }

    // MARK: - Private

    private func registerBGTask() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: Self.taskIdentifier, using: nil) { [weak self] task in
            guard let self else {
                task.setTaskCompleted(success: false)
                return
            }
            Task { @MainActor in
                await self.performAutoBlockBack()
                self.scheduleBackgroundTask()
                task.setTaskCompleted(success: true)
            }
        }
    }

    /// Loads the target lists whose IDs are stored in UserDefaults.
    private func loadTargetLists(
        account: AppAccount,
        appPassword: String,
        using client: LiveBlueskyClient
    ) async -> [BlueskyList] {
        guard let ids = try? JSONDecoder().decode([String].self, from: targetListIDsData),
              !ids.isEmpty else { return [] }

        var result: [BlueskyList] = []

        // Fetch remote lists and internal lists
        var allLists: [BlueskyList] = []
        if let remote = try? await client.fetchLists(for: account, appPassword: appPassword) {
            allLists = remote
        }
        if let store = internalListStore {
            let internalLists = store.lists.map { il in
                BlueskyList(
                    id: "internal:\(il.id.uuidString)",
                    name: il.name,
                    description: "Internal",
                    memberCount: il.memberCount,
                    kind: .internal,
                    cid: nil
                )
            }
            allLists.append(contentsOf: internalLists)
        }

        // Filter to only configured IDs, preserving selection order
        let listMap = Dictionary(uniqueKeysWithValues: allLists.map { ($0.id, $0) })
        for id in ids {
            if let list = listMap[id] {
                result.append(list)
            }
        }
        return result
    }

    /// Adds an actor to a target list. For internal lists, uses direct `InternalListStore` add;
    /// for external lists, uses the Bluesky API.
    private func addActorToTargetList(
        did: String,
        handle: String,
        list: BlueskyList,
        account: AppAccount,
        appPassword: String,
        using client: LiveBlueskyClient
    ) async throws {
        if list.kind == .internal, let store = internalListStore {
            let listID = store.listID(from: list.id)
            store.addMember(did: did, handle: handle, to: listID)
        } else {
            _ = try await client.addActor(did: did, to: list, account: account, appPassword: appPassword)
        }
    }

    private func sendNotification(
        blockedCount: Int,
        failedCount: Int,
        listNames: [String]
    ) async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized ||
              settings.authorizationStatus == .provisional else { return }

        let content = UNMutableNotificationContent()

        if !listNames.isEmpty {
            let joined = ListFormatter.localizedString(byJoining: listNames)
            if failedCount > 0 {
                content.title = String.localized("autoblock.notification.title_lists_partial")
                content.body = String.localized(
                    "autoblock.notification.body_lists_partial",
                    replacements: [
                        "blocked": "\(blockedCount)",
                        "failed": "\(failedCount)",
                        "lists": joined,
                    ]
                )
            } else {
                content.title = String.localized("autoblock.notification.title_lists")
                content.body = String.localized(
                    "autoblock.notification.body_lists",
                    replacements: [
                        "count": "\(blockedCount)",
                        "lists": joined,
                    ]
                )
            }
        } else if failedCount > 0 {
            content.title = String.localized("autoblock.notification.title_partial")
            content.body = String.localized(
                "autoblock.notification.body_partial",
                replacements: [
                    "blocked": "\(blockedCount)",
                    "failed": "\(failedCount)",
                ]
            )
        } else {
            content.title = String.localized("autoblock.notification.title")
            content.body = String.localized(
                "autoblock.notification.body",
                replacements: ["count": "\(blockedCount)"]
            )
        }

        content.sound = .default
        content.interruptionLevel = .timeSensitive

        let request = UNNotificationRequest(
            identifier: "autoblockback-\(Date.now.timeIntervalSince1970)",
            content: content,
            trigger: nil
        )
        try? await center.add(request)
    }
}
