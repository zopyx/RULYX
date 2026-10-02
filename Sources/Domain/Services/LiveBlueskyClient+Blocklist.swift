import Foundation

// MARK: - Blocklist sources ("Blocking" / "Blocked by" / "Listed on")

//
// Lives outside `LiveBlueskyClient.swift` to keep that file inside its swiftlint
// `file_length` gate. Only the source reads live here: **Swift forbids overriding a method
// declared in an extension**, so everything `PreviewBlueskyClient` substitutes (the
// `fetchBlockedActors` / `fetchBlockedByActors` / `fetchBlocking…` / `fetchBlockedBy…` /
// `fetchUnblockedBlockersCount` entry points) stays in the class body and calls these.
//
// `httpClient`, `resolveAccountDID`, `resolveHandleToDID` and `resolveProfilesBestEffort`
// are declared `internal` in the main file on purpose: Swift's `private` is file-scoped, so
// an extension in another file cannot see them.

extension LiveBlueskyClient {
    // MARK: - "Blocked by" (Constellation backlink index)

    /// DIDs of the accounts blocking `account`.
    ///
    /// The index is keyed on the link *target*, so the `app.bsky.graph.block` records that
    /// point at the account are exactly its blockers — and its own `total` is exact.
    func constellationBlockerDIDs(account: AppAccount) async throws -> Set<String> {
        try await constellation.blockerDIDs(actorDID: resolveAccountDID(account))
    }

    /// Every blocker of `actorDID` with the block's date, mapped onto the shared
    /// `BlocklistEntry` shape so the Block Back diff can consume either side uniformly.
    private func blockerEntries(actorDID: String) async throws -> [BlocklistEntry] {
        let entries = try await constellation.blockerEntries(actorDID: actorDID, onProgress: nil).entries
        return entries.map { BlocklistEntry(did: $0.did, blockedDate: $0.blockedDate) }
    }

    // MARK: - "Blocking" (the account's own repo)

    /// DIDs of the accounts blocked by `account` — the `subject` of every
    /// `app.bsky.graph.block` record in its own repo.
    func repoBlockedDIDs(account: AppAccount) async throws -> Set<String> {
        try await Set(repo.blockRecords(for: account, onProgress: nil).map(\.did))
    }

    /// The account's own block records as actors, profiles resolved best-effort and each
    /// block dated from the record.
    ///
    /// Internal (not private): the overridable `fetchBlockedActors` in the class body
    /// routes through it.
    func repoBlockedActors(
        account: AppAccount,
        onProgress: (@MainActor @Sendable (Int) async -> Void)?
    ) async throws -> BlocklistResult {
        let records = try await repo.blockRecords(for: account, onProgress: onProgress)
        guard !records.isEmpty else { return BlocklistResult(actors: [], totalCount: 0) }

        var blockedDates = [String: String]()
        for record in records where blockedDates[record.did] == nil {
            blockedDates[record.did] = record.createdAt
        }

        var actors = await resolveProfilesBestEffort(dids: Array(blockedDates.keys).sorted())
        for index in actors.indices {
            if let dateString = blockedDates[actors[index].did] {
                actors[index].blockedDate = parseDate(dateString)
            }
        }
        return BlocklistResult(actors: actors, totalCount: records.count)
    }

    // MARK: - Block Back diff

    /// The actors that block the account but are not blocked back: the index's blockers
    /// minus the account's own block records, profiles resolved best-effort and sorted by
    /// block date descending.
    func fetchUnblockedBlockerActors(account: AppAccount, appPassword _: String?) async throws -> [BlueskyActor] {
        let actorDID = try await resolveAccountDID(account)

        // Fetch blocked (actors we block) and blocked-by (actors that block us) in parallel.
        async let blockedDIDsTask = fetchBlockedDIDs(for: account)
        async let blockedByTask = blockerEntries(actorDID: actorDID)
        let (blockedDIDs, blockedByEntries) = try await (blockedDIDsTask, blockedByTask)

        // Filter to only those that block us but aren't on our blocklist.
        let candidateEntries = blockedByEntries.filter { !blockedDIDs.contains($0.did) }
        guard !candidateEntries.isEmpty else { return [] }

        var blockedDates = [String: String]()
        for entry in candidateEntries {
            blockedDates[entry.did] = entry.blockedDate
        }

        var result = await resolveProfilesBestEffort(dids: candidateEntries.map(\.did))
        for index in result.indices {
            if let dateString = blockedDates[result[index].did] {
                result[index].blockedDate = parseDate(dateString)
            }
        }

        return result.sorted { ($0.blockedDate ?? .distantPast) > ($1.blockedDate ?? .distantPast) }
    }

    // MARK: - "Listed on"

    /// Number of lists the profile appears on.
    ///
    /// A membership is an `app.bsky.graph.listitem` record whose `subject` is the profile;
    /// the index groups those by their `list` link, so the count is the number of **distinct
    /// lists**, not of membership records (a profile re-added to a list has one record per
    /// addition).
    func fetchListedOnCount(handle: String, did: String?) async throws -> Int {
        let actorDID = try await listedOnActorDID(handle: handle, did: did)
        return try await constellation.listedOnListCount(actorDID: actorDID)
    }

    /// The lists a profile appears on, for the "Listed on" screen: memberships from the
    /// index, list metadata from the public AppView — see `ListedOnListResolver`.
    /// `onProgress` reports the phase and, once known, how many lists are resolved.
    func fetchListedOnLists(
        handle: String,
        did: String?,
        onProgress: (@MainActor @Sendable (ListedOnProgress) async -> Void)? = nil
    ) async throws -> [ListedOnListEntry] {
        let actorDID = try await listedOnActorDID(handle: handle, did: did)
        return try await listedOnResolver.entries(for: actorDID, onProgress: onProgress)
    }

    /// The DID the "Listed on" queries run against. Callers normally already know it (the
    /// profile being viewed); only a handle falls back to AT Protocol resolution.
    private func listedOnActorDID(handle: String, did: String?) async throws -> String {
        if let did, !did.isEmpty {
            return did
        }
        return try await resolveHandleToDID(handle: handle)
    }
}
