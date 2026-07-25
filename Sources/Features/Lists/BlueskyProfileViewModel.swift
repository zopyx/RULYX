import Foundation
import Observation

/// Metadata about a moderation list that is blocking the inspected profile.
struct BlockingListInfo: Identifiable, Hashable {
    let id: String
    let name: String
    let listURI: String?
    let memberCount: Int?
}

/// Manages inspection, moderation actions, and data export for a single Bluesky profile.
///
/// Supports reading viewer state (block/mute/follow), toggling moderation actions,
/// fetching list memberships, owned/subscribed lists, ClearSky data, media counts,
/// handle history, and post export. Uses optimistic pending states for instant UI feedback.
@MainActor
@Observable
final class BlueskyProfileViewModel {
    // MARK: - Properties

    /// The full profile inspection result (profile + list memberships + starter packs).
    private(set) var inspection: ProfileInspection?
    /// True while the initial profile load is in progress.
    private(set) var isLoading = false
    /// True while a moderation toggles (block/mute/follow) is executing.
    private(set) var isUpdatingModeration = false
    /// Handle change history from the PLC audit log.
    private(set) var handleHistory: [HandleChange] = []
    /// Total image count across all scanned posts.
    private(set) var mediaImageCount = 0
    /// Total video count across all scanned posts.
    private(set) var mediaVideoCount = 0
    /// True while scanning posts for media content.
    private(set) var isScanningMedia = false
    /// User-facing success message (e.g. "Account muted."), auto-cleared on next load.
    var statusMessage: String?
    /// User-facing error message.
    var errorMessage: String?
    /// True while generating a post export file.
    private(set) var isExportingPosts = false
    /// Localized label shown during export (page count / writing status).
    private(set) var exportProgressLabel: String?
    /// Error that occurred during post export.
    var exportError: String?
    /// Lists from ClearSky that contain this profile.
    private(set) var clearskyLists: [ClearskyListEntry] = []
    /// True while fetching ClearSky list data.
    private(set) var isFetchingLists = false
    /// Error from ClearSky list fetch.
    var listError: String?
    /// Optimistic pending state for follow toggle (nil = resolved).
    private(set) var pendingFollowingState: Bool?
    /// Optimistic pending state for block toggle (nil = resolved).
    private(set) var pendingBlockState: Bool?
    /// Optimistic pending state for mute toggle (nil = resolved).
    private(set) var pendingMuteState: Bool?
    /// Per-list optimistic pending states for membership toggles (nil = resolved).
    private(set) var pendingListMemberStates: [String: Bool] = [:]
    /// True when the report sheet is presented.
    var showReportSheet = false
    /// True while a report is being submitted.
    var isReporting = false
    /// The selected report reason for the current report.
    var selectedReportReason = ModerationReportReasonType.simplifiedDefault
    /// Lists owned/created by this profile.
    private(set) var ownedLists: [BlueskyList]?
    /// True while fetching owned lists.
    private(set) var isFetchingOwnedLists = false
    /// True while fetching list memberships after initial load.
    private(set) var isFetchingMemberships = false
    /// True while toggling a list membership.
    private(set) var isUpdatingListMembership = false
    /// Moderation lists that the viewer subscribes to.
    private(set) var subscribedLists: [SubscribedListInfo]?
    /// Names of subscribed moderation lists blocking this profile.
    private(set) var subscribedListBlockingNames: [String] = []
    /// Combined list of all blocking names (owned memberships + subscribed lists).
    private(set) var combinedBlockingNames: [String] = []
    /// Structs combining name, URI, and count for each blocking list.
    private(set) var blockingLists: [BlockingListInfo] = []
    /// True while fetching subscribed moderation lists.
    private(set) var isFetchingSubscribedLists = false
    /// True while creating a new list and adding the profile to it.
    private(set) var isCreatingList = false

    // MARK: - Computed Properties

    /// True if the profile is blocked by at least one moderation list.
    var isBlockedByList: Bool {
        !combinedBlockingNames.isEmpty
    }

    // MARK: - Account Switch

    /// Resets all inspection state so no viewer-relative data from the previous
    /// account remains visible. Called before reloading after an account switch.
    func reset() {
        inspection = nil
        isLoading = false
        isUpdatingModeration = false
        handleHistory = []
        mediaImageCount = 0
        mediaVideoCount = 0
        isScanningMedia = false
        statusMessage = nil
        errorMessage = nil
        clearskyLists = []
        isFetchingLists = false
        listError = nil
        pendingFollowingState = nil
        pendingBlockState = nil
        pendingMuteState = nil
        pendingListMemberStates = [:]
        ownedLists = nil
        isFetchingOwnedLists = false
        isFetchingMemberships = false
        isUpdatingListMembership = false
        subscribedLists = nil
        subscribedListBlockingNames = []
        combinedBlockingNames = []
        blockingLists = []
        isFetchingSubscribedLists = false
        isCreatingList = false
    }

    // MARK: - Private Methods

    /// Merges blocking-by-list names from viewer state, owned list memberships, and subscribed lists.
    private func recomputeCombinedBlockingNames(from viewerState: BlueskyViewerState?) {
        var names = Set(viewerState?.blockingByListName ?? [])
        for membership in listMemberships where membership.kind == .moderation && membership.isMember {
            names.insert(membership.name)
        }
        for name in subscribedListBlockingNames {
            names.insert(name)
        }
        combinedBlockingNames = Array(names).sorted()
        blockingLists = buildBlockingLists(from: combinedBlockingNames)
    }

    /// Converts blocking list names into `BlockingListInfo` structs with URI and member count if available.
    private func buildBlockingLists(from names: [String]) -> [BlockingListInfo] {
        names.map { name in
            if let membership = listMemberships.first(where: { $0.name == name && $0.kind == .moderation }) {
                return BlockingListInfo(id: membership.listURI, name: name, listURI: membership.listURI, memberCount: membership.memberCount)
            }
            if let info = subscribedLists?.first(where: { $0.name == name && $0.kind == .moderation }) {
                return BlockingListInfo(id: info.listURI, name: name, listURI: info.listURI, memberCount: info.memberCount)
            }
            return BlockingListInfo(id: name, name: name, listURI: nil, memberCount: nil)
        }
    }

    // MARK: - List Data Fetching

    /// Fetches lists that the profile owns/created.
    func fetchOwnedLists(did: String, account: AppAccount, appPassword: String, using client: any BlueskyListServicing) async {
        isFetchingOwnedLists = true
        do {
            ownedLists = try await client.fetchActorLists(actor: did, account: account, appPassword: appPassword)
                .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        } catch {
            AppLogger.moderation.error("Owned lists fetch failed: \(error.localizedDescription, privacy: .private)")
            ownedLists = []
        }
        isFetchingOwnedLists = false
    }

    /// Fetches the viewer's subscribed moderation lists and checks if the target profile appears in any of them.
    /// - Parameter targetDID: The profile DID to check against each list; if nil, skips membership checking.
    func fetchSubscribedLists(account: AppAccount, appPassword: String, using client: LiveBlueskyClient, targetDID: String? = nil) async {
        isFetchingSubscribedLists = true
        do {
            subscribedLists = try await client.fetchSubscribedModerationLists(account: account, appPassword: appPassword)
                .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

            if let targetDID, let lists = subscribedLists {
                let moderationSubs = lists.filter { $0.kind == .moderation }
                var blockingNames: [String] = []
                for list in moderationSubs {
                    var cursor: String?
                    var found = false
                    var pagesChecked = 0
                    let bskyList = BlueskyList(
                        id: list.listURI,
                        name: list.name,
                        description: list.description ?? "",
                        memberCount: list.memberCount,
                        kind: list.kind
                    )
                    // Check up to 2 pages of each list to find the target
                    while !found, pagesChecked < 2 {
                        let page: PagedListMembers
                        do {
                            page = try await client.fetchListMembersPage(
                                list: bskyList, cursor: cursor,
                                account: account, appPassword: appPassword
                            )
                        } catch {
                            AppLogger.moderation.error("Failed to fetch list members page: \(error.localizedDescription, privacy: .private)")
                            break
                        }
                        found = page.members.contains(where: { $0.actor.did == targetDID })
                        cursor = page.cursor
                        pagesChecked += 1
                        if cursor == nil {
                            break
                        }
                    }
                    if found {
                        blockingNames.append(list.name)
                    }
                }
                subscribedListBlockingNames = blockingNames.sorted()
                recomputeCombinedBlockingNames(from: inspection?.profile.viewerState)
            }
        } catch {
            AppLogger.moderation.error("Subscribed lists fetch failed: \(error.localizedDescription, privacy: .private)")
            subscribedLists = []
        }
        isFetchingSubscribedLists = false
    }

    /// Fetches ClearSky public lists that contain the given handle.
    func fetchClearskyLists(handle: String, using client: LiveBlueskyClient) async {
        isFetchingLists = true
        listError = nil
        do {
            clearskyLists = try await client.fetchClearskyLists(handle: handle)
        } catch {
            listError = error.localizedDescription
            AppLogger.moderation.error("Clearsky lists failed: \(error.localizedDescription, privacy: .private)")
        }
        isFetchingLists = false
    }

    // MARK: - Private Properties

    /// Guards against re-loading the profile data on every view appearance.
    private var hasLoadedOnce = false
    private let downloadService = MediaDownloadService.shared

    // MARK: - Convenience Accessors

    /// The decoded `BlueskyProfile` from the current inspection.
    var profile: BlueskyProfile? {
        inspection?.profile
    }

    /// List memberships from the current inspection, sorted alphabetically by name within each kind group.
    var listMemberships: [ProfileListMembership] {
        (inspection?.listMemberships ?? []).sorted { lhs, rhs in
            if lhs.kind != rhs.kind {
                return lhs.kind.sortOrder < rhs.kind.sortOrder
            }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    // MARK: - Profile Loading

    /// Loads profile data only if it hasn't been loaded yet (guarded by `hasLoadedOnce`).
    func loadIfNeeded(
        did actorDID: String,
        viewerAccount: AppAccount,
        viewerPassword: String,
        dataAccount: AppAccount,
        dataPassword: String,
        using client: LiveBlueskyClient
    ) async {
        guard !hasLoadedOnce else { return }
        await load(did: actorDID, account: viewerAccount, viewerPassword: viewerPassword, dataAccount: dataAccount, dataPassword: dataPassword, using: client)
    }

    /// Loads (or reloads) the full profile inspection: profile data, viewer state, handle history, media counts, and list memberships.
    ///
    /// - Parameters:
    ///   - viewerAccount: Account used for viewer-state queries (block/mute/follow status).
    ///   - dataAccount: Account used for data queries (list memberships, media counting).
    func load(
        did actorDID: String,
        account viewerAccount: AppAccount,
        viewerPassword: String,
        dataAccount: AppAccount,
        dataPassword: String,
        using client: LiveBlueskyClient
    ) async {
        isLoading = true
        errorMessage = nil
        statusMessage = nil
        hasLoadedOnce = true

        do {
            let result = try await client.inspectProfile(
                query: actorDID,
                account: viewerAccount,
                appPassword: viewerPassword
            )
            inspection = result
            if !result.listMemberships.isEmpty {
                recomputeCombinedBlockingNames(from: result.profile.viewerState)
            } else {
                isFetchingMemberships = true
            }
            // Clear stale pending states — fresh API data is now authoritative
            pendingBlockState = nil
            pendingMuteState = nil
            pendingFollowingState = nil
            pendingListMemberStates = [:]
        } catch {
            hasLoadedOnce = false
            errorMessage = AppError.userMessage(from: error)
            isLoading = false
            return
        }

        isLoading = false
        guard let profile else { return }

        // Fetch handle history and media counts in parallel (non-blocking — load() returns immediately)
        async let auditLog = client.fetchPLCAuditLog(did: profile.did)
        async let mediaCount = countMedia(for: profile.did, account: dataAccount, appPassword: dataPassword, using: client)

        // Deferred membership fetch if not available from inspection
        if isFetchingMemberships {
            let memberships = await client.fetchListMemberships(for: profile.did, account: dataAccount, appPassword: dataPassword)
            if !memberships.isEmpty {
                inspection = ProfileInspection(profile: profile, listMemberships: memberships, starterPackMemberships: inspection?.starterPackMemberships ?? [])
            }
            isFetchingMemberships = false
        }

        recomputeCombinedBlockingNames(from: inspection?.profile.viewerState)

        // Handle history (media count already completed in background)
        if let log = try? await auditLog {
            handleHistory = parseHandleChanges(from: log, currentHandle: profile.handle)
        }
        await mediaCount
    }

    // MARK: - Private Helpers

    /// Scans the user's feed counting images and videos.
    ///
    /// Optimizations:
    /// - Caps at 1000 posts (10 pages of 100) to bound execution time
    /// - Caches results in `BlueskyAPICache` with 5-minute TTL
    /// - Checks cache before scanning; skips entirely on cache hit
    private func countMedia(for did: String, account: AppAccount, appPassword: String, using client: LiveBlueskyClient) async {
        let cacheKey = "mediaScan_\(did)"

        // Check cache first
        let cached = await BlueskyAPICache.shared.read(accountDID: did, url: cacheKey, maxAge: BlueskyAPICache.DefaultTTL.member)
        if let cachedData = cached, !cachedData.isStale {
            if let counts = try? JSONDecoder().decode(MediaScanResult.self, from: cachedData.data) {
                mediaImageCount = counts.images
                mediaVideoCount = counts.videos
                return
            }
        }

        isScanningMedia = true
        defer { isScanningMedia = false }

        let maxPages = 10 // 1000 posts max
        var cursor: String?
        var images = 0
        var videos = 0
        var pagesFetched = 0

        while pagesFetched < maxPages {
            guard !Task.isCancelled else { return }
            do {
                let response = try await client.fetchRichFeed(did: did, cursor: cursor, account: account, appPassword: appPassword)
                pagesFetched += 1
                for entry in response.feed {
                    guard !Task.isCancelled else { return }
                    if let embed = entry.post.embed {
                        images += embed.images?.count ?? 0
                        if embed.video != nil {
                            videos += 1
                        }
                    }
                }
                cursor = response.cursor
                if cursor == nil {
                    break
                }
            } catch is CancellationError {
                return
            } catch {
                break
            }
        }

        mediaImageCount = images
        mediaVideoCount = videos

        // Write to cache
        let result = MediaScanResult(images: images, videos: videos)
        if let encoded = try? JSONEncoder().encode(result) {
            await BlueskyAPICache.shared.write(accountDID: did, url: cacheKey, data: encoded)
        }
    }

    // MARK: - Moderation Actions

    /// Optimistically toggles the mute state for the profile.
    /// Keeps the pending state until the next successful load() to
    /// avoid visual revert due to PDS propagation delay.
    func toggleMute(
        account: AppAccount,
        appPassword: String,
        using client: LiveBlueskyClient
    ) async {
        guard let profile else { return }
        let isCurrentlyMuted = pendingMuteState ?? profile.viewerState?.muted ?? false
        let newState = !isCurrentlyMuted

        isUpdatingModeration = true
        pendingMuteState = newState
        defer {
            isUpdatingModeration = false
        }

        do {
            if isCurrentlyMuted {
                try await client.unmuteActor(
                    did: profile.did,
                    account: account,
                    appPassword: appPassword
                )
                statusMessage = String.localized("profile.status.unmuted")
            } else {
                try await client.muteActor(
                    did: profile.did,
                    account: account,
                    appPassword: appPassword
                )
                statusMessage = String.localized("profile.status.muted")
            }

            // Don't call load() here — avoids PDS propagation delay
        } catch {
            errorMessage = AppError.userMessage(from: error)
            pendingMuteState = isCurrentlyMuted
        }
    }

    /// Submits a moderation report for the profile with the selected reason.
    func reportAccount(reason: String?, account: AppAccount, appPassword: String, using client: LiveBlueskyClient) async {
        guard let profile else { return }

        isReporting = true
        defer {
            isReporting = false
            showReportSheet = false
        }

        do {
            try await client.reportAccount(
                did: profile.did,
                selectedReason: selectedReportReason,
                reason: reason,
                account: account,
                appPassword: appPassword
            )
            statusMessage = loc("actions.done")
        } catch {
            errorMessage = AppError.userMessage(from: error)
        }
    }

    /// Optimistically toggles the follow state for the profile.
    /// Keeps the pending state until the next successful load() to
    /// avoid visual revert due to PDS propagation delay.
    func toggleFollow(
        account: AppAccount,
        appPassword: String,
        using client: LiveBlueskyClient
    ) async {
        guard let profile else { return }
        let isCurrentlyFollowing = pendingFollowingState ?? profile.viewerState?.isFollowing ?? false
        let newState = !isCurrentlyFollowing

        isUpdatingModeration = true
        pendingFollowingState = newState
        defer {
            isUpdatingModeration = false
            // pendingFollowingState intentionally NOT cleared here —
            // stays set until load() confirms the new state from the PDS
        }

        do {
            if let recordURI = profile.viewerState?.followingRecordURI,
               isCurrentlyFollowing
            {
                try await client.unfollowActor(
                    recordURI: recordURI,
                    account: account,
                    appPassword: appPassword
                )
            } else {
                try await client.followActor(
                    did: profile.did,
                    account: account,
                    appPassword: appPassword
                )
            }

            statusMessage = nil
            // Don't call load() here — avoids PDS propagation delay
        } catch {
            errorMessage = AppError.userMessage(from: error)
            pendingFollowingState = isCurrentlyFollowing
        }
    }

    /// True while downloading the latest images from the profile's feed.
    var isDownloadingImages = false
    /// Tracks (currentBatch, totalBatches, totalImages) during image download.
    var downloadProgress: (currentBatch: Int, totalBatches: Int, totalImages: Int)?

    /// Downloads up to 500 images from the profile's recent posts to the specified directory.
    /// - Parameter directory: The parent directory; images are saved to `directory/handle/`.
    func downloadLatestImages(to directory: URL, account: AppAccount, appPassword: String, using client: LiveBlueskyClient) async {
        guard let profile else { return }

        isDownloadingImages = true
        defer { isDownloadingImages = false }

        let targetDir = directory.appendingPathComponent(profile.handle, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: targetDir, withIntermediateDirectories: true)
        } catch {
            AppLogger.moderation.error("Failed to create image download directory: \(error.localizedDescription, privacy: .private)")
        }

        var allImageURLs: [String] = []
        var cursor: String?

        while allImageURLs.count < 500 {
            do {
                guard !Task.isCancelled else { return }
                let page = try await client.fetchAuthorFeed(did: profile.did, cursor: cursor, account: account, appPassword: appPassword)
                for feedPost in page.feed {
                    guard !Task.isCancelled else { return }
                    guard let images = feedPost.post.embed?.images else { continue }
                    for img in images where allImageURLs.count < 500 {
                        allImageURLs.append(img.fullsize)
                    }
                }
                guard let nextCursor = page.cursor else { break }
                cursor = nextCursor
            } catch is CancellationError {
                return
            } catch {
                break
            }
        }

        guard !allImageURLs.isEmpty else {
            statusMessage = String.localized("profile.status.no_images")
            return
        }

        let totalBatches = (allImageURLs.count + 9) / 10
        let assets = allImageURLs.enumerated().compactMap { index, urlString -> MediaAssetDownload? in
            guard let url = URL(string: urlString) else { return nil }
            let preferredExtension = url.pathExtension.isEmpty ? nil : url.pathExtension
            return MediaAssetDownload(
                index: index,
                filenameStem: "image-\(index + 1)",
                source: .image(url: url, preferredExtension: preferredExtension)
            )
        }

        let results = await downloadService.downloadImages(assets, to: targetDir) { completed, _, _ in
            await MainActor.run {
                let currentBatch = min(totalBatches, max(1, (completed + 9) / 10))
                self.downloadProgress = (currentBatch, totalBatches, allImageURLs.count)
            }
        }
        guard !Task.isCancelled else { return }

        let succeeded = results.count(where: { $0.savedFilename != nil })
        statusMessage = String.localized("profile.status.images_downloaded", replacements: ["count": "\(succeeded)", "handle": profile.handle])
    }

    /// Optimistically toggles the block state for the profile.
    /// Keeps the pending state until the next successful load() to
    /// avoid visual revert due to PDS propagation delay.
    func toggleBlock(
        account: AppAccount,
        appPassword: String,
        using client: LiveBlueskyClient
    ) async {
        guard let profile else { return }
        let isCurrentlyBlocking = pendingBlockState ?? profile.viewerState?.isBlocking ?? false
        let newState = !isCurrentlyBlocking

        isUpdatingModeration = true
        pendingBlockState = newState
        defer {
            isUpdatingModeration = false
            // pendingBlockState intentionally NOT cleared here —
            // stays set until load() confirms the new state from the PDS,
            // avoiding visual revert due to propagation delay
        }

        do {
            if let recordURI = profile.viewerState?.blockingRecordURI,
               isCurrentlyBlocking
            {
                try await client.unblockActor(
                    recordURI: recordURI,
                    account: account,
                    appPassword: appPassword
                )
                statusMessage = String.localized("profile.status.unblocked")
            } else {
                try await client.blockActor(
                    did: profile.did,
                    account: account,
                    appPassword: appPassword
                )
                statusMessage = String.localized("profile.status.blocked")
            }

            // Don't call load() here — PDS may not have indexed the new
            // block record yet, returning stale viewerState and reverting
            // the toggle. The pending state persists until the next
            // explicit load() (e.g. on next profile visit).
        } catch {
            errorMessage = AppError.userMessage(from: error)
            pendingBlockState = isCurrentlyBlocking
        }
    }

    /// True while fetching and queueing followers for blocking.
    var isBlockingFollowers = false
    /// Progress information for the block-followers operation.
    var blockFollowersProgress: BatchProgress?

    /// Fetches all followers and enqueues them as block operations in the `ActionQueueStore`.
    func blockAllFollowers(
        account: AppAccount,
        appPassword: String,
        using client: LiveBlueskyClient,
        queue: ActionQueueStore
    ) async {
        guard let profile else { return }

        isBlockingFollowers = true
        defer { isBlockingFollowers = false }

        do {
            let followers = try await client.fetchFollowers(
                actor: profile.did,
                account: account,
                appPassword: appPassword
            )

            guard !followers.isEmpty else {
                statusMessage = String.localized("profile.status.no_followers")
                return
            }

            statusMessage = String.localized("profile.status.queued_followers", replacements: ["count": "\(followers.count)"])

            queue.enqueue(QueuedAction(
                title: "Block followers of \(profile.handle)",
                actors: followers,
                operation: .block
            ) { actor in
                try await client.blockActor(
                    did: actor.did,
                    account: account,
                    appPassword: appPassword
                )
            })
        } catch {
            errorMessage = AppError.userMessage(from: error)
        }
    }

    /// Optimistically toggles whether the profile is a member of a specific list.
    func toggleListMembership(
        _ membership: ProfileListMembership,
        account: AppAccount,
        appPassword: String,
        using client: LiveBlueskyClient
    ) async {
        guard let profile else { return }
        let isCurrentlyMember = pendingListMemberStates[membership.listURI] ?? membership.isMember

        isUpdatingListMembership = true
        pendingListMemberStates[membership.listURI] = !isCurrentlyMember
        defer {
            isUpdatingListMembership = false
            // pendingListMemberStates intentionally NOT cleared here —
            // stays set until load() confirms the new state from the PDS
        }

        do {
            if isCurrentlyMember, let recordURI = membership.listItemRecordURI {
                try await client.removeMember(
                    recordURI: recordURI,
                    account: account,
                    appPassword: appPassword
                )
                statusMessage = String.localized("profile.status.removed_from_list", replacements: ["name": membership.name])
            } else {
                guard let list = try await client.fetchList(
                    uri: membership.listURI,
                    account: account,
                    appPassword: appPassword
                ) else {
                    throw BlueskyAPIError.server("That list could not be loaded.")
                }

                _ = try await client.addActor(
                    did: profile.did,
                    to: list,
                    account: account,
                    appPassword: appPassword
                )
                statusMessage = String.localized("profile.status.added_to_list", replacements: ["name": membership.name])
            }

            // Don't call load() here — avoids PDS propagation delay
        } catch {
            errorMessage = AppError.userMessage(from: error)
            pendingListMemberStates[membership.listURI] = isCurrentlyMember
        }
    }

    /// Creates a new list (of the given kind) and immediately adds the profile to it.
    func createListAndAddActor(
        name: String,
        description: String,
        kind: BlueskyList.Kind,
        account: AppAccount,
        appPassword: String,
        using client: LiveBlueskyClient
    ) async {
        guard let profile else { return }

        isCreatingList = true
        defer { isCreatingList = false }

        do {
            let newList = try await client.createList(
                name: name,
                description: description,
                kind: kind,
                account: account,
                appPassword: appPassword
            )

            _ = try await client.addActor(
                did: profile.did,
                to: newList,
                account: account,
                appPassword: appPassword
            )

            statusMessage = String.localized("profile.status.list_created", replacements: ["name": name, "handle": profile.handle])

            await load(
                did: profile.did,
                account: account,
                viewerPassword: appPassword,
                dataAccount: account,
                dataPassword: appPassword,
                using: client
            )
        } catch {
            errorMessage = AppError.userMessage(from: error)
        }
    }

    // MARK: - Export

    /// Enumerates all pages of the profile's posts and exports them as CSV or JSON.
    /// - Returns: The file URL of the exported file, or nil if cancelled or failed.
    func exportPosts(as format: ExportFileFormat, account: AppAccount, appPassword: String, using client: LiveBlueskyClient) async -> URL? {
        guard let profile else { return nil }
        isExportingPosts = true
        exportError = nil
        defer {
            isExportingPosts = false
            exportProgressLabel = nil
        }

        var allPosts: [RichFeedEntry] = []
        var cursor: String?
        var pageCount = 0
        while true {
            guard !Task.isCancelled else { return nil }
            pageCount += 1
            let postCount = allPosts.count
            exportProgressLabel = loc("profile.export.loading")
                .replacingOccurrences(of: "{n}", with: "\(pageCount)")
                .replacingOccurrences(of: "{posts}", with: "\(postCount)")

            let response: RichFeedResponse
            do {
                response = try await client.fetchRichFeed(did: profile.did, cursor: cursor, account: account, appPassword: appPassword)
            } catch is CancellationError {
                return nil
            } catch {
                AppLogger.moderation.error("Export page \(pageCount) failed: \(error.localizedDescription, privacy: .private)")
                if cursor == nil {
                    exportError = AppError.userMessage(from: error)
                    return nil
                }
                try? await Task.sleep(for: .seconds(2))
                continue
            }

            let profilePosts = response.feed.filter { $0.post.author?.did == profile.did }
            allPosts += profilePosts

            guard let next = response.cursor, !next.isEmpty else { break }
            cursor = next
        }

        guard !Task.isCancelled else { return nil }
        exportProgressLabel = loc("profile.export.writing")

        let sanitized = profile.handle.replacingOccurrences(of: ".", with: "-")
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(sanitized)-posts.\(format.rawValue)")

        switch format {
        case .csv:
            let header = "uri,author_did,author_handle,text,created_at,reply_count,repost_count,like_count"
            let rows = allPosts.map { entry -> String in
                let p = entry.post
                let a = p.safeAuthor
                let text = (p.safeRecord.text ?? "").replacingOccurrences(of: "\"", with: "\"\"")
                return [
                    p.uri,
                    a.did ?? "",
                    a.handle ?? "",
                    "\"\(text)\"",
                    p.safeRecord.createdAt ?? "",
                    "\(p.replyCount ?? 0)",
                    "\(p.repostCount ?? 0)",
                    "\(p.likeCount ?? 0)",
                ].joined(separator: ",")
            }
            let csv = ([header] + rows).joined(separator: "\n")
            try? csv.write(to: url, atomically: true, encoding: .utf8)
        case .json:
            let objects = allPosts.map { entry -> [String: Any] in
                let p = entry.post
                let a = p.safeAuthor
                return [
                    "uri": p.uri,
                    "author_did": a.did ?? "",
                    "author_handle": a.handle ?? "",
                    "author_display_name": a.displayName ?? "",
                    "text": p.safeRecord.text ?? "",
                    "created_at": p.safeRecord.createdAt ?? "",
                    "reply_count": p.replyCount ?? 0,
                    "repost_count": p.repostCount ?? 0,
                    "like_count": p.likeCount ?? 0,
                    "has_images": p.embed?.images?.isEmpty == false,
                    "has_video": p.embed?.video != nil,
                ] as [String: Any]
            }
            let data = (try? JSONSerialization.data(withJSONObject: objects, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])) ?? Data()
            try? data.write(to: url, options: .atomic)
        }
        return url
    }
}

/// Supported post export file formats.
enum ExportFileFormat: String, CaseIterable {
    /// Comma-separated values with a header row.
    case csv
    /// Pretty-printed JSON array of post objects.
    case json
}

/// Cached result of a media scan for a profile.
private struct MediaScanResult: Codable {
    let images: Int
    let videos: Int
}
