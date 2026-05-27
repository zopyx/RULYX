import Foundation

// MARK: - Search, add/remove single actor, and membership filtering

extension ListDetailViewModel {
    /// Summary string describing the current search results count.
    var searchResultSummary: String {
        if hasMoreSearchResults {
            return "Showing \(searchResults.count) matches so far."
        }

        return "\(searchResults.count) matching account\(searchResults.count == 1 ? "" : "s")."
    }

    /// Searches for actors to add to the list. Minimum 2-character query.
    /// Filters out actors already in the member list.
    /// - Stale-query guard: if `lastSearchQuery` changes during the request, the result is discarded.
    func search(
        query: String,
        account: AppAccount,
        appPassword: String,
        using client: LiveBlueskyClient
    ) async {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        lastSearchQuery = trimmed

        guard trimmed.count >= 2 else {
            searchResults = []
            searchCursor = nil
            hasMoreSearchResults = false
            isSearching = false
            return
        }

        let start = CFAbsoluteTimeGetCurrent()
        isSearching = true
        searchErrorMessage = nil

        do {
            let page = try await client.searchActorsPage(
                query: trimmed,
                cursor: nil,
                account: account,
                appPassword: appPassword
            )
            guard trimmed == lastSearchQuery else {
                isSearching = false
                return
            }
            searchResults = filteredSearchResults(page.actors)
            searchCursor = page.cursor
            hasMoreSearchResults = page.cursor != nil
            selectedSearchActorIDs = selectedSearchActorIDs.intersection(Set(searchResults.map(\.id)))
        } catch {
            searchErrorMessage = AppError.userMessage(from: error)
            searchResults = []
            selectedSearchActorIDs = []
            searchCursor = nil
            hasMoreSearchResults = false
        }

        AppLogger.performance.debug("search for '\(trimmed, privacy: .public)' took \(CFAbsoluteTimeGetCurrent() - start, format: .fixed(precision: 2))s")
        isSearching = false
    }

    /// Loads the next page of search results.
    func loadMoreSearchResults(
        account: AppAccount,
        appPassword: String,
        using client: LiveBlueskyClient
    ) async {
        guard hasMoreSearchResults,
              !isSearching,
              !isLoadingMoreSearchResults,
              lastSearchQuery.count >= 2,
              let cursor = searchCursor
        else {
            return
        }
        let requestQuery = lastSearchQuery
        let requestCursor = cursor

        isLoadingMoreSearchResults = true
        defer { isLoadingMoreSearchResults = false }

        do {
            let page = try await client.searchActorsPage(
                query: requestQuery,
                cursor: requestCursor,
                account: account,
                appPassword: appPassword
            )
            guard requestQuery == lastSearchQuery, requestCursor == searchCursor else {
                return
            }
            searchResults = filteredSearchResults(searchResults + page.actors)
            searchCursor = page.cursor
            hasMoreSearchResults = page.cursor != nil
            selectedSearchActorIDs = selectedSearchActorIDs.intersection(Set(searchResults.map(\.id)))
        } catch {
            searchErrorMessage = AppError.userMessage(from: error)
        }
    }

    /// Adds a single actor to the list and updates local state.
    func add(
        actor: BlueskyActor,
        to list: BlueskyList,
        account: AppAccount,
        appPassword: String,
        using client: LiveBlueskyClient
    ) async {
        batchProgressState.addingActorIDs.insert(actor.did)
        defer { batchProgressState.addingActorIDs.remove(actor.did) }

        do {
            let recordURI = try await client.addActor(
                did: actor.did,
                to: list,
                account: account,
                appPassword: appPassword
            )
            searchResults.removeAll { $0.did == actor.did }
            selectedSearchActorIDs.remove(actor.id)
            members.append(BlueskyListMember(recordURI: recordURI, actor: actor))
            onMembersChanged()
            refreshSearchMembershipFilter()
        } catch {
            errorMessage = AppError.userMessage(from: error)
        }
    }

    /// Removes a single member from the list and updates local state.
    func remove(
        member: BlueskyListMember,
        account: AppAccount,
        appPassword: String,
        using client: LiveBlueskyClient
    ) async {
        batchProgressState.removingMemberIDs.insert(member.id)
        defer { batchProgressState.removingMemberIDs.remove(member.id) }

        do {
            try await client.removeMember(
                recordURI: member.recordURI,
                account: account,
                appPassword: appPassword
            )
            members.removeAll { $0.id == member.id }
            selectedMemberIDs.remove(member.id)
            onMembersChanged()
        } catch {
            errorMessage = AppError.userMessage(from: error)
        }
    }

    /// True if a given actor is currently being added (optimistic state).
    func isAdding(_ actor: BlueskyActor) -> Bool {
        batchProgressState.isAdding(actor)
    }

    /// True if a given member is currently being removed (optimistic state).
    func isRemoving(_ member: BlueskyListMember) -> Bool {
        batchProgressState.isRemoving(member)
    }

    /// Filters out actors who are already members of the list, and deduplicates by DID.
    func filteredSearchResults(_ actors: [BlueskyActor]) -> [BlueskyActor] {
        let existing = Set(members.map(\.actor.did))
        var deduplicated: [BlueskyActor] = []
        var seen: Set<String> = []

        for actor in actors where !existing.contains(actor.did) {
            if seen.insert(actor.did).inserted {
                deduplicated.append(actor)
            }
        }

        return deduplicated
    }

    /// Re-filters the current search results after members change.
    func refreshSearchMembershipFilter() {
        searchResults = filteredSearchResults(searchResults)
        selectedSearchActorIDs = selectedSearchActorIDs.intersection(Set(searchResults.map(\.id)))
    }
}
