import Foundation

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
final class BlueskyProfileViewModel: ObservableObject {
    // MARK: - Properties

    /// The full profile inspection result (profile + list memberships + starter packs).
    @Published private(set) var inspection: ProfileInspection?
    /// True while the initial profile load is in progress.
    @Published private(set) var isLoading = false
    /// True while a moderation toggles (block/mute/follow) is executing.
    @Published private(set) var isUpdatingModeration = false
    /// Handle change history from the PLC audit log.
    @Published private(set) var handleHistory: [HandleChange] = []
    /// Total image count across all scanned posts.
    @Published private(set) var mediaImageCount = 0
    /// Total video count across all scanned posts.
    @Published private(set) var mediaVideoCount = 0
    /// True while scanning posts for media content.
    @Published private(set) var isScanningMedia = false
    /// User-facing success message (e.g. "Account muted."), auto-cleared on next load.
    @Published var statusMessage: String?
    /// User-facing error message.
    @Published var errorMessage: String?
    /// True while generating a post export file.
    @Published private(set) var isExportingPosts = false
    /// Localized label shown during export (page count / writing status).
    @Published private(set) var exportProgressLabel: String?
    /// Error that occurred during post export.
    @Published var exportError: String?
    /// Lists from ClearSky that contain this profile.
    @Published private(set) var clearskyLists: [ClearskyListEntry] = []
    /// True while fetching ClearSky list data.
    @Published private(set) var isFetchingLists = false
    /// Error from ClearSky list fetch.
    @Published var listError: String?
    /// Optimistic pending state for follow toggle (nil = resolved).
    @Published private(set) var pendingFollowingState: Bool?
    /// Optimistic pending state for block toggle (nil = resolved).
    @Published private(set) var pendingBlockState: Bool?
    /// Optimistic pending state for mute toggle (nil = resolved).
    @Published private(set) var pendingMuteState: Bool?
    /// Per-list optimistic pending states for membership toggles (nil = resolved).
    @Published private(set) var pendingListMemberStates: [String: Bool] = [:]
    /// True when the report sheet is presented.
    @Published var showReportSheet = false
    /// True while a report is being submitted.
    @Published var isReporting = false
    /// The selected report reason for the current report.
    @Published var selectedReportReason = ModerationReportReasonType.simplifiedDefault
    /// Lists owned/created by this profile.
    @Published private(set) var ownedLists: [BlueskyList]?
    /// True while fetching owned lists.
    @Published private(set) var isFetchingOwnedLists = false
    /// True while fetching list memberships after initial load.
    @Published private(set) var isFetchingMemberships = false
    /// True while toggling a list membership.
    @Published private(set) var isUpdatingListMembership = false
    /// Moderation lists that the viewer subscribes to.
    @Published private(set) var subscribedLists: [SubscribedListInfo]?
    /// Names of subscribed moderation lists blocking this profile.
    @Published private(set) var subscribedListBlockingNames: [String] = []
    /// Combined list of all blocking names (owned memberships + subscribed lists).
    @Published private(set) var combinedBlockingNames: [String] = []
    /// Structs combining name, URI, and count for each blocking list.
    @Published private(set) var blockingLists: [BlockingListInfo] = []
    /// True while fetching subscribed moderation lists.
    @Published private(set) var isFetchingSubscribedLists = false
    /// True while creating a new list and adding the profile to it.
    @Published private(set) var isCreatingList = false

    // MARK: - Computed Properties

    /// True if the profile is blocked by at least one moderation list.
    var isBlockedByList: Bool {
        !combinedBlockingNames.isEmpty
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
    func fetchOwnedLists(did: String, account: AppAccount, appPassword: String, using client: LiveBlueskyClient) async {
        isFetchingOwnedLists = true
        do {
            ownedLists = try await client.fetchActorLists(actor: did, account: account, appPassword: appPassword)
        } catch {
            AppLogger.moderation.error("Owned lists fetch failed: \(error.localizedDescription, privacy: .public)")
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
                    // Check up to 5 pages of each list to find the target
                    while !found, pagesChecked < 5 {
                        guard let page = try? await client.fetchListMembersPage(
                            list: bskyList, cursor: cursor,
                            account: account, appPassword: appPassword
                        ) else { break }
                        found = page.members.contains(where: { $0.actor.did == targetDID })
                        cursor = page.cursor
                        pagesChecked += 1
                        if cursor == nil { break }
                    }
                    if found { blockingNames.append(list.name) }
                }
                subscribedListBlockingNames = blockingNames.sorted()
                recomputeCombinedBlockingNames(from: inspection?.profile.viewerState)
            }
        } catch {
            AppLogger.moderation.error("Subscribed lists fetch failed: \(error.localizedDescription, privacy: .public)")
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
            AppLogger.moderation.error("Clearsky lists failed: \(error.localizedDescription, privacy: .public)")
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

    /// List memberships from the current inspection.
    var listMemberships: [ProfileListMembership] {
        inspection?.listMemberships ?? []
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
        } catch {
            hasLoadedOnce = false
            errorMessage = AppError.userMessage(from: error)
            isLoading = false
            return
        }

        isLoading = false
        guard let profile else { return }

        // Fetch handle history and media counts in parallel
        async let auditLog = client.fetchPLCAuditLog(did: profile.did)
        await countMedia(for: profile.did, account: dataAccount, appPassword: dataPassword, using: client)

        if let log = try? await auditLog {
            handleHistory = parseHandleChanges(from: log, currentHandle: profile.handle)
        }

        // Deferred membership fetch if not available from inspection
        if isFetchingMemberships {
            let memberships = await client.fetchListMemberships(for: profile.did, account: dataAccount, appPassword: dataPassword)
            if !memberships.isEmpty {
                inspection = ProfileInspection(profile: profile, listMemberships: memberships, starterPackMemberships: inspection?.starterPackMemberships ?? [])
            }
            isFetchingMemberships = false
        }

        recomputeCombinedBlockingNames(from: inspection?.profile.viewerState)
    }

    // MARK: - Private Helpers

    /// Scans the user's feed counting images and videos. Stops when all pages are exhausted or cancelled.
    private func countMedia(for did: String, account: AppAccount, appPassword: String, using client: LiveBlueskyClient) async {
        isScanningMedia = true
        defer { isScanningMedia = false }
        var cursor: String?
        var images = 0
        var videos = 0
        while true {
            do {
                guard !Task.isCancelled else { return }
                let response = try await client.fetchRichFeed(did: did, cursor: cursor, account: account, appPassword: appPassword)
                for entry in response.feed {
                    guard !Task.isCancelled else { return }
                    if let embed = entry.post.embed {
                        images += embed.images?.count ?? 0
                        if embed.video != nil { videos += 1 }
                    }
                }
                guard let next = response.cursor else { break }
                cursor = next
            } catch is CancellationError {
                return
            } catch {
                break
            }
        }
        mediaImageCount = images
        mediaVideoCount = videos
    }

    // MARK: - Moderation Actions

    /// Optimistically toggles the mute state for the profile.
    func toggleMute(
        account: AppAccount,
        appPassword: String,
        using client: LiveBlueskyClient
    ) async {
        guard let profile else { return }
        let isCurrentlyMuted = pendingMuteState ?? profile.viewerState?.muted ?? false

        isUpdatingModeration = true
        pendingMuteState = !isCurrentlyMuted
        defer {
            isUpdatingModeration = false
            pendingMuteState = nil
        }

        do {
            if isCurrentlyMuted {
                try await client.unmuteActor(
                    did: profile.did,
                    account: account,
                    appPassword: appPassword
                )
                statusMessage = "Account unmuted."
            } else {
                try await client.muteActor(
                    did: profile.did,
                    account: account,
                    appPassword: appPassword
                )
                statusMessage = "Account muted."
            }

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
    func toggleFollow(
        account: AppAccount,
        appPassword: String,
        using client: LiveBlueskyClient
    ) async {
        guard let profile else { return }
        let isCurrentlyFollowing = pendingFollowingState ?? profile.viewerState?.isFollowing ?? false

        isUpdatingModeration = true
        pendingFollowingState = !isCurrentlyFollowing
        defer {
            isUpdatingModeration = false
            pendingFollowingState = nil
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

    /// True while downloading the latest images from the profile's feed.
    @Published var isDownloadingImages = false
    /// Tracks (currentBatch, totalBatches, totalImages) during image download.
    @Published var downloadProgress: (currentBatch: Int, totalBatches: Int, totalImages: Int)?

    /// Downloads up to 500 images from the profile's recent posts to the specified directory.
    /// - Parameter directory: The parent directory; images are saved to `directory/handle/`.
    func downloadLatestImages(to directory: URL, account: AppAccount, appPassword: String, using client: LiveBlueskyClient) async {
        guard let profile else { return }

        isDownloadingImages = true
        defer { isDownloadingImages = false }

        let targetDir = directory.appendingPathComponent(profile.handle, isDirectory: true)
        try? FileManager.default.createDirectory(at: targetDir, withIntermediateDirectories: true)

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
            statusMessage = "No images found in recent posts."
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
        statusMessage = "Downloaded \(succeeded) images to \(profile.handle)/."
    }

    /// Optimistically toggles the block state for the profile.
    func toggleBlock(
        account: AppAccount,
        appPassword: String,
        using client: LiveBlueskyClient
    ) async {
        guard let profile else { return }
        let isCurrentlyBlocking = pendingBlockState ?? profile.viewerState?.isBlocking ?? false

        isUpdatingModeration = true
        pendingBlockState = !isCurrentlyBlocking
        defer {
            isUpdatingModeration = false
            pendingBlockState = nil
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
                statusMessage = "Account unblocked."
            } else {
                try await client.blockActor(
                    did: profile.did,
                    account: account,
                    appPassword: appPassword
                )
                statusMessage = "Account blocked."
            }

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

    /// True while fetching and queueing followers for blocking.
    @Published var isBlockingFollowers = false
    /// Progress information for the block-followers operation.
    @Published var blockFollowersProgress: BatchProgress?

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
                statusMessage = "No followers to block."
                return
            }

            statusMessage = "Queued \(followers.count) followers for blocking."

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
            pendingListMemberStates[membership.listURI] = nil
        }

        do {
            if isCurrentlyMember, let recordURI = membership.listItemRecordURI {
                try await client.removeMember(
                    recordURI: recordURI,
                    account: account,
                    appPassword: appPassword
                )
                statusMessage = "Removed from \(membership.name)."
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
                statusMessage = "Added to \(membership.name)."
            }

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

            statusMessage = "Created \"\(name)\" and added \(profile.handle)."

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
                AppLogger.moderation.error("Export page \(pageCount) failed: \(error.localizedDescription, privacy: .public)")
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
