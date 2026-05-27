import SwiftUI

/// Manages the lifecycle of bulk liker actions: fetching all likers of a post,
/// confirming block-all-likers, adding likers to moderation/internal/regular lists,
/// classifying a post, and submitting reports.
///
/// This is an `ObservableObject` meant to be owned at the timeline/feed level
/// and shared across all post rows via `PostLikerActionsViewModifier`.
@MainActor
class PostLikerActionsManager: ObservableObject {
    @Published var availableTargetLists: [BlueskyList] = []
    @Published var isFetchingLikers = false
    @Published var pendingLikerTargets: [PendingLikerTarget] = []
    @Published var showBlockLikersConfirmation = false
    @Published var blockError: String?
    @Published var batchOperationConfig: BatchOperationConfig?
    @Published var postToClassify: RichFeedEntry?
    @Published var postToReport: RichFeedEntry?
    @Published var reportReason = ModerationReportReasonType.simplifiedDefault
    @Published var reportEvidence = ""
    @Published var isSubmittingReport = false

    /// Fetch the user's moderation, internal, and regular lists as potential targets for "add likers".
    func loadAvailableTargetLists(using blueskyClient: LiveBlueskyClient, internalListStore: InternalListStore? = nil, account: AppAccount, appPassword: String) async {
        var lists: [BlueskyList] = []
        do {
            lists = try await blueskyClient.fetchLists(for: account, appPassword: appPassword)
        } catch {
            AppLogger.moderation.error("Failed to load available target lists: \(error.localizedDescription, privacy: .public)")
        }
        if let internalListStore {
            let internalLists = internalListStore.lists.map { internalList in
                BlueskyList(
                    id: "internal:\(internalList.id.uuidString)",
                    name: internalList.name,
                    description: "Internal",
                    memberCount: internalList.memberCount,
                    kind: .internal,
                    cid: nil
                )
            }
            lists.append(contentsOf: internalLists)
        }
        availableTargetLists = lists.sorted { lhs, rhs in
            if lhs.kind != rhs.kind {
                return lhs.kind.sortOrder < rhs.kind.sortOrder
            }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    /// Begin the "block all likers" flow: fetch likers, build pending targets,
    /// then set `showBlockLikersConfirmation` to present the confirmation alert.
    func handleBlockAllLikers(postURI: String, using blueskyClient: LiveBlueskyClient, fetchAccount: AppAccount, fetchPassword: String) {
        Task {
            guard let targets = await fetchLikerTargets(for: postURI, using: blueskyClient, fetchAccount: fetchAccount, fetchPassword: fetchPassword) else { return }
            pendingLikerTargets = targets
            showBlockLikersConfirmation = true
        }
    }

    /// Begin the "add all likers to list" flow: fetch likers, then either add to internal list
    /// directly or set `batchOperationConfig` for external list addition.
    func handleAddAllLikersToList(postURI: String, list: BlueskyList, using blueskyClient: LiveBlueskyClient, fetchAccount: AppAccount, fetchPassword: String, activeAccount: AppAccount, activePassword: String, internalListStore: InternalListStore? = nil) {
        if list.kind == .internal, let internalListStore {
            Task {
                guard let targets = await fetchLikerTargets(for: postURI, using: blueskyClient, fetchAccount: fetchAccount, fetchPassword: fetchPassword) else { return }
                for target in targets {
                    internalListStore.addMember(did: target.did, handle: target.handle ?? target.did, to: internalListID(from: list.id))
                }
            }
        } else {
            Task {
                guard let targets = await fetchLikerTargets(for: postURI, using: blueskyClient, fetchAccount: fetchAccount, fetchPassword: fetchPassword) else { return }
                guard !targets.isEmpty else { return }
                batchOperationConfig = BatchOperationConfig(
                    targets: targets,
                    mode: .addToList(list: list, account: activeAccount, appPassword: activePassword)
                )
            }
        }
    }

    /// Called from the confirmation alert — commits the pending block operation.
    func confirmBlockLikers(activeAccount: AppAccount, activePassword: String) {
        guard !pendingLikerTargets.isEmpty else { return }
        let targets = pendingLikerTargets
        resetPendingLikerTargets()
        batchOperationConfig = BatchOperationConfig(
            targets: targets,
            mode: .block(account: activeAccount, appPassword: activePassword)
        )
    }

    /// Clear the pending liker targets and dismiss the confirmation alert.
    func resetPendingLikerTargets() {
        pendingLikerTargets = []
        showBlockLikersConfirmation = false
    }

    /// Build a `SupportEmailDraft` for reporting the given post via email.
    func makeReportDraft(for entry: RichFeedEntry) -> SupportEmailDraft {
        let author = entry.post.author
        let handle = author?.handle ?? "unknown"
        let text = entry.post.safeRecord.text ?? ""
        return SupportEmailDraft(
            subject: "Bluesky Post Report — @\(handle)",
            body: SupportEmailDraft.htmlBody(
                intro: "I am reporting the following Bluesky post for review.",
                fields: [
                    ("Author Handle", "@\(handle)"),
                    ("Author DID", author?.did ?? "—"),
                    ("Post URI", entry.post.uri),
                    ("Post CID", entry.post.cid ?? "—"),
                    ("Post Text", text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "—" : text),
                    ("Reason", reportReason.localizedTitle),
                    ("Additional Details", reportEvidence.isEmpty ? "—" : reportEvidence),
                ],
                footer: "Evidence screenshot attached below if provided."
            )
        )
    }

    /// Submit a post report via the Bluesky API.
    func submitPostReport(using blueskyClient: LiveBlueskyClient, account: AppAccount, appPassword: String) async {
        guard let entry = postToReport, let cid = entry.post.cid else { return }
        isSubmittingReport = true
        do {
            try await blueskyClient.reportRecord(
                uri: entry.post.uri,
                cid: cid,
                reason: reportEvidence.isEmpty ? nil : reportEvidence,
                selectedReason: reportReason,
                account: account,
                appPassword: appPassword
            )
            postToReport = nil
            reportEvidence = ""
            reportReason = .simplifiedDefault
        } catch {
            AppLogger.moderation.error("Post report failed: \(error.localizedDescription, privacy: .public)")
        }
        isSubmittingReport = false
    }

    // MARK: - Private Helpers

    /// Strip `"internal:"` prefix from composite ID to get a bare UUID.
    private func internalListID(from compositeID: String) -> UUID {
        let stripped = compositeID.replacingOccurrences(of: "internal:", with: "")
        return UUID(uuidString: stripped) ?? UUID()
    }

    /// Fetch all likers for a post (paginated) and return deduplicated `PendingLikerTarget` objects.
    private func fetchLikerTargets(for postURI: String, using blueskyClient: LiveBlueskyClient, fetchAccount: AppAccount, fetchPassword: String) async -> [PendingLikerTarget]? {
        isFetchingLikers = true
        resetPendingLikerTargets()
        do {
            var allLikes: [LikeItem] = []
            var cursor: String?
            repeat {
                let response = try await blueskyClient.fetchLikes(uri: postURI, cursor: cursor, account: fetchAccount, appPassword: fetchPassword)
                allLikes += response.likes
                cursor = response.cursor
            } while cursor != nil
            isFetchingLikers = false
            let targets = collectPendingLikerTargets(from: allLikes)
            if targets.isEmpty {
                blockError = loc("post.block_likers.no_likers")
                return nil
            }
            return targets
        } catch {
            isFetchingLikers = false
            blockError = AppError.userMessage(from: error)
            return nil
        }
    }

    /// Deduplicate likers by DID.
    private func collectPendingLikerTargets(from likes: [LikeItem]) -> [PendingLikerTarget] {
        var seenDIDs = Set<String>()
        return likes.compactMap { like in
            guard let did = like.actor.did, !did.isEmpty else { return nil }
            guard seenDIDs.insert(did).inserted else { return nil }
            return PendingLikerTarget(
                did: did,
                handle: like.actor.handle
            )
        }
    }
}
