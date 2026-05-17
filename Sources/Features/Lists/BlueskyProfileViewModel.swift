import Foundation

@MainActor
final class BlueskyProfileViewModel: ObservableObject {
    @Published private(set) var inspection: ProfileInspection?
    @Published private(set) var isLoading = false
    @Published private(set) var isUpdatingModeration = false
    @Published private(set) var handleHistory: [HandleChange] = []
    @Published private(set) var mediaImageCount = 0
    @Published private(set) var mediaVideoCount = 0
    @Published private(set) var isScanningMedia = false
    @Published var statusMessage: String?
    @Published var errorMessage: String?
    @Published private(set) var isExportingPosts = false
    @Published private(set) var clearskyLists: [ClearskyListEntry] = []
    @Published private(set) var isFetchingLists = false
    @Published var listError: String?
    @Published private(set) var pendingFollowingState: Bool?
    @Published private(set) var pendingBlockState: Bool?
    @Published private(set) var pendingMuteState: Bool?
    @Published private(set) var pendingListMemberStates: [String: Bool] = [:]

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

    private var hasLoadedOnce = false
    private let downloadService = MediaDownloadService.shared

    var profile: BlueskyProfile? {
        inspection?.profile
    }

    var listMemberships: [ProfileListMembership] {
        inspection?.listMemberships ?? []
    }

    func loadIfNeeded(
        did actorDID: String,
        account: AppAccount,
        appPassword: String,
        using client: LiveBlueskyClient
    ) async {
        guard !hasLoadedOnce else { return }
        await load(did: actorDID, account: account, appPassword: appPassword, using: client)
    }

    func load(
        did actorDID: String,
        account: AppAccount,
        appPassword: String,
        using client: LiveBlueskyClient
    ) async {
        isLoading = true
        errorMessage = nil
        statusMessage = nil
        hasLoadedOnce = true

        do {
            inspection = try await client.inspectProfile(
                query: actorDID,
                account: account,
                appPassword: appPassword
            )
        } catch {
            hasLoadedOnce = false
            inspection = nil
            handleHistory = []
            errorMessage = AppError.userMessage(from: error)
            isLoading = false
            return
        }

        isLoading = false
        guard let profile else { return }

        async let auditLog = client.fetchPLCAuditLog(did: profile.did)
        await countMedia(for: profile.did, account: account, appPassword: appPassword, using: client)

        if let log = try? await auditLog {
            handleHistory = parseHandleChanges(from: log, currentHandle: profile.handle)
        }
    }

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
                appPassword: appPassword,
                using: client
            )
        } catch {
            errorMessage = AppError.userMessage(from: error)
        }
    }

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
                appPassword: appPassword,
                using: client
            )
        } catch {
            errorMessage = AppError.userMessage(from: error)
        }
    }

    @Published var isDownloadingImages = false
    @Published var downloadProgress: (currentBatch: Int, totalBatches: Int, totalImages: Int)?

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
                appPassword: appPassword,
                using: client
            )
        } catch {
            errorMessage = AppError.userMessage(from: error)
        }
    }

    @Published var isBlockingFollowers = false
    @Published var blockFollowersProgress: BatchProgress?

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

    func toggleListMembership(
        _ membership: ProfileListMembership,
        account: AppAccount,
        appPassword: String,
        using client: LiveBlueskyClient
    ) async {
        guard let profile else { return }
        let isCurrentlyMember = pendingListMemberStates[membership.listURI] ?? membership.isMember

        isUpdatingModeration = true
        pendingListMemberStates[membership.listURI] = !isCurrentlyMember
        defer {
            isUpdatingModeration = false
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
                appPassword: appPassword,
                using: client
            )
        } catch {
            errorMessage = AppError.userMessage(from: error)
        }
    }

    func exportPosts(as format: ExportFileFormat, account: AppAccount, appPassword: String, using client: LiveBlueskyClient) async -> URL? {
        guard let profile else { return nil }
        isExportingPosts = true
        defer { isExportingPosts = false }

        var allPosts: [RichFeedEntry] = []
        var cursor: String?
        while true {
            do {
                guard !Task.isCancelled else { return nil }
                let response = try await client.fetchRichFeed(did: profile.did, cursor: cursor, account: account, appPassword: appPassword)
                allPosts += response.feed
                guard let next = response.cursor else { break }
                cursor = next
            } catch is CancellationError {
                return nil
            } catch {
                break
            }
        }

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
            let data = (try? JSONSerialization.data(withJSONObject: objects, options: [.prettyPrinted, .sortedKeys])) ?? Data()
            try? data.write(to: url, options: .atomic)
        }
        return url
    }
}

enum ExportFileFormat: String, CaseIterable {
    case csv
    case json
}
