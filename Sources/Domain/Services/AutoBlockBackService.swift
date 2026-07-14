import BackgroundTasks
import SwiftUI
import UserNotifications

// MARK: - AutoBlockBackService

/// Periodically checks for accounts that block the user but aren't blocked back,
/// and automatically blocks them. Optionally also adds them to configured
/// moderation/curation/internal lists.
///
/// Triggered on app foreground and via `BGAppRefreshTask` (best-effort background).
///
/// Controlled by:
/// - `@AppStorage("autoBlockBackEnabled")` (default: `true`)
/// - `@AppStorage("autoBlockBackIntervalMinutes")` (default: `30`)
/// - `@AppStorage("autoBlockTargetListIDs")` — JSON-encoded `[String]` of list IDs
///
/// Interval options (in minutes):
/// - `0` = never (don't auto-run in background; manual only via foreground trigger)
/// - `5` = every 5 minutes
/// - `20` = every 20 minutes
/// - `60` = every hour
/// - `360` = every 6 hours
/// - `1440` = once per day
@MainActor
final class AutoBlockBackService: ObservableObject {
    // MARK: - Interval

    /// Predefined notification intervals for the Settings picker.
    enum Interval: Int, CaseIterable, Identifiable {
        case never = 0
        case fiveMinutes = 5
        case twentyMinutes = 20
        case oneHour = 60
        case sixHours = 360
        case oneDay = 1440

        var id: Int {
            rawValue
        }

        var labelKey: String {
            switch self {
            case .never: "autoblock.interval.never"
            case .fiveMinutes: "autoblock.interval.5min"
            case .twentyMinutes: "autoblock.interval.20min"
            case .oneHour: "autoblock.interval.1hour"
            case .sixHours: "autoblock.interval.6hours"
            case .oneDay: "autoblock.interval.1day"
            }
        }
    }

    // MARK: - Constants

    private static let taskIdentifier = "com.ajung.RULYX.autoblockback"
    private static let lastRunKey = "autoBlockBackLastRunTimestamp"

    // MARK: - Properties

    @AppStorage("autoBlockBackEnabled") var isEnabled = true
    @AppStorage("autoBlockBackIntervalMinutes") var intervalMinutes = 30
    @AppStorage("autoBlockTargetListIDs") private var targetListIDsData = Data()

    @Published private(set) var isRunning = false
    @Published private(set) var lastResult: Result?

    private weak var container: BlueskyServiceContainerWrapper?
    private var clearskyService: BlueskyClearSkyServicing?
    private var profileService: BlueskyProfileInspecting?
    private var listService: BlueskyListServicing?
    private var socialService: BlueskySocialServicing?
    private weak var accountStore: AccountStoreProtocol?
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

    /// Creates the service with the required dependencies.
    init(
        clearskyService: BlueskyClearSkyServicing,
        profileService: BlueskyProfileInspecting,
        listService: BlueskyListServicing,
        socialService: BlueskySocialServicing,
        accountStore: AccountStoreProtocol,
        internalListStore: InternalListStore
    ) {
        self.clearskyService = clearskyService
        self.profileService = profileService
        self.listService = listService
        self.socialService = socialService
        self.accountStore = accountStore
        self.internalListStore = internalListStore
        registerBGTask()
    }

    /// Convenience initializer using BlueskyServiceContainerWrapper (production use).
    convenience init(
        container: BlueskyServiceContainerWrapper,
        accountStore: AccountStoreProtocol,
        internalListStore: InternalListStore
    ) {
        self.init(
            clearskyService: container.clearsky,
            profileService: container.profile,
            listService: container.list,
            socialService: container.social,
            accountStore: accountStore,
            internalListStore: internalListStore
        )
        self.container = container
    }

    // MARK: - Public API

    /// Performs the auto-block-back check and operation. Safe to call from
    /// foreground or background. Posts a local notification with the count
    /// of newly blocked accounts and list additions.
    func performAutoBlockBack() async {
        guard isEnabled else { return }
        guard !isRunning else { return }

        // Check interval: skip if not enough time has passed since last run
        if intervalMinutes > 0 {
            let lastRun = UserDefaults.standard.double(forKey: Self.lastRunKey)
            if lastRun > 0 {
                let elapsed = Date.now.timeIntervalSince1970 - lastRun
                let minimumInterval = Double(intervalMinutes) * 60.0
                if elapsed < minimumInterval {
                    return
                }
            }
        }

        guard let clearsky = clearskyService,
              let profile = profileService,
              let listSvc = listService,
              let social = socialService,
              let account = accountStore?.activeAccount,
              let appPassword = accountStore?.appPassword(for: account) else { return }

        isRunning = true
        defer { isRunning = false }

        do {
            let toBlock = try await clearsky.fetchUnblockedBlockerActors(
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

            // P0: Pre-filter against PDS-level block records to avoid duplicates.
            let existingBlockedDIDs: Set<String>
            do {
                existingBlockedDIDs = try await profile.fetchExistingBlockedDIDs(
                    account: account, appPassword: appPassword
                )
            } catch {
                existingBlockedDIDs = []
                AppLogger.moderation.error(
                    "Auto-block-back: failed to fetch existing block DIDs, falling back to ClearSky data: \(error.localizedDescription, privacy: .public)"
                )
            }
            let filteredToBlock = toBlock.filter { !existingBlockedDIDs.contains($0.did) }
            guard !filteredToBlock.isEmpty else {
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
                using: listSvc
            )

            var blocked = 0
            var failed = 0

            // Batch execution: batches of 5 with 300ms delay between batches
            let batchSize = 5
            for batchStart in stride(from: 0, to: filteredToBlock.count, by: batchSize) {
                let batchEnd = min(batchStart + batchSize, filteredToBlock.count)
                let batch = filteredToBlock[batchStart ..< batchEnd]

                await withTaskGroup(of: (Bool, BlueskyActor).self) { group in
                    for actor in batch {
                        group.addTask {
                            do {
                                try await social.blockActor(
                                    did: actor.did, account: account, appPassword: appPassword
                                )
                                return (true, actor)
                            } catch {
                                let errorDesc = error.localizedDescription
                                let nsError = error as NSError
                                let underlyingErrors = nsError.underlyingErrors.map(\.localizedDescription).joined(separator: "; ")
                                let detail = underlyingErrors.isEmpty ? "" : " [underlying: \(underlyingErrors)]"
                                AppLogger.moderation.error(
                                    "Auto-block-back failed for \(actor.handle, privacy: .public): \(errorDesc, privacy: .public)\(detail, privacy: .public)"
                                )
                                return (false, actor)
                            }
                        }
                    }

                    for await (success, actor) in group {
                        if success {
                            blocked += 1
                            // Add to configured lists
                            for list in targetLists {
                                do {
                                    try await addActorToTargetList(
                                        did: actor.did,
                                        handle: actor.handle,
                                        list: list,
                                        account: account,
                                        appPassword: appPassword,
                                        using: listSvc
                                    )
                                } catch {
                                    AppLogger.moderation.error(
                                        "Auto-block-back: failed to add \(actor.handle, privacy: .public) to list \(list.name, privacy: .public): \(error.localizedDescription, privacy: .public)"
                                    )
                                }
                            }
                        } else {
                            failed += 1
                        }
                    }
                }

                if batchEnd < filteredToBlock.count {
                    try? await Task.sleep(for: .milliseconds(300))
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

            // Record last successful run timestamp
            UserDefaults.standard.set(Date.now.timeIntervalSince1970, forKey: Self.lastRunKey)

            if blocked > 0 {
                await sendNotification(
                    blockedCount: blocked,
                    failedCount: failed,
                    listNames: listNames
                )
            }
        } catch let BlueskyAPIError.pdsUnreachable(host) {
            AppLogger.moderation.error(
                "Auto-block-back skipped: active account PDS (\(host)) is unreachable."
            )
            lastResult = Result(
                blockedCount: 0, failedCount: 0,
                addedToListCount: 0, listNames: [],
                timestamp: .now
            )
        } catch {
            AppLogger.moderation.error(
                "Auto-block-back fetch failed: \(error.localizedDescription, privacy: .public)"
            )
        }
    }

    /// Schedules the next `BGAppRefreshTask`. Call when the app enters background.
    func scheduleBackgroundTask() {
        guard isEnabled else { return }
        // Never run in background if interval is 0
        guard intervalMinutes > 0 else { return }
        let request = BGAppRefreshTaskRequest(identifier: Self.taskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: Double(intervalMinutes) * 60.0)
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
    func loadTargetLists(
        account: AppAccount,
        appPassword: String,
        using listService: BlueskyListServicing
    ) async -> [BlueskyList] {
        guard let ids = try? JSONDecoder().decode([String].self, from: targetListIDsData),
              !ids.isEmpty else { return [] }

        var result: [BlueskyList] = []

        // Fetch remote lists and internal lists
        var allLists: [BlueskyList] = []
        do {
            allLists = try await listService.fetchLists(for: account, appPassword: appPassword)
        } catch {
            AppLogger.moderation.error(
                "Auto-block-back: failed to fetch lists for target list matching: \(error.localizedDescription, privacy: .public)"
            )
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
        let listMap = Dictionary(allLists.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for id in ids {
            if let list = listMap[id] {
                result.append(list)
            }
        }
        return result
    }

    /// Adds an actor to a target list. For internal lists, uses direct `InternalListStore` add;
    /// for external lists, uses the Bluesky API.
    func addActorToTargetList(
        did: String,
        handle: String,
        list: BlueskyList,
        account: AppAccount,
        appPassword: String,
        using listService: BlueskyListServicing
    ) async throws {
        if list.kind == .internal, let store = internalListStore {
            let listID = store.listID(from: list.id)
            store.addMember(did: did, handle: handle, to: listID)
        } else {
            _ = try await listService.addActor(did: did, to: list, account: account, appPassword: appPassword)
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
