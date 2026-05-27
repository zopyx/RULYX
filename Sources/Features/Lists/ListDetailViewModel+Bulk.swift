import Foundation

// MARK: - Bulk selection, add/remove/mute/block/transfer, and batch operations

extension ListDetailViewModel {
    // MARK: - Selection Helpers

    /// True if the actor is selected in the search results for bulk add.
    func isSelectedForBulkAdd(_ actor: BlueskyActor) -> Bool {
        selectedSearchActorIDs.contains(actor.id)
    }

    /// True if the member is selected for bulk removal.
    func isSelectedForBulkRemoval(_ member: BlueskyListMember) -> Bool {
        selectedMemberIDs.contains(member.id)
    }

    /// Toggles an actor's selection in the search results.
    func toggleSearchSelection(for actor: BlueskyActor) {
        if !selectedSearchActorIDs.insert(actor.id).inserted {
            selectedSearchActorIDs.remove(actor.id)
        }
    }

    /// Toggles a member's selection in the member list.
    func toggleMemberSelection(for member: BlueskyListMember) {
        if !selectedMemberIDs.insert(member.id).inserted {
            selectedMemberIDs.remove(member.id)
        }
    }

    /// Toggles an actor DID in the comparison selection.
    func toggleComparisonSelection(for actorDID: String) {
        if !selectedComparisonActorDIDs.insert(actorDID).inserted {
            selectedComparisonActorDIDs.remove(actorDID)
        }
    }

    /// Selects all search results for bulk add.
    func selectAllSearchResults() {
        selectedSearchActorIDs = Set(searchResults.map(\.id))
    }

    /// Clears the search result selection.
    func clearSearchSelection() {
        selectedSearchActorIDs.removeAll()
    }

    /// Selects all members matching the current filter.
    func selectAllFilteredMembers() {
        selectedMemberIDs = Set(filteredMembers.map(\.id))
    }

    /// Clears the member selection.
    func clearMemberSelection() {
        selectedMemberIDs.removeAll()
    }

    /// Selects all members in a given comparison bucket.
    func selectComparisonBucket(_ bucket: ComparisonBucket) {
        guard let comparisonReport else { return }
        selectedComparisonActorDIDs = diffController.selectComparisonBucket(bucket, in: comparisonReport)
    }

    /// Clears the comparison selection.
    func clearComparisonSelection() {
        selectedComparisonActorDIDs.removeAll()
    }

    // MARK: - Bulk Operations

    /// Adds all selected search-result actors to the list.
    func bulkAddSelectedActors(
        to list: BlueskyList,
        account: AppAccount,
        appPassword: String,
        using client: LiveBlueskyClient
    ) async {
        let selectedActors = searchResults.filter { selectedSearchActorIDs.contains($0.id) }
        guard !selectedActors.isEmpty else { return }

        let result = await performActorBatch(
            title: "Adding selected results",
            actors: selectedActors,
            operation: .add
        ) { actor in
            _ = try await client.addActor(
                did: actor.did,
                to: list,
                account: account,
                appPassword: appPassword
            )
        }

        bulkActionResult = result
        searchResults.removeAll { actor in
            result.succeededActors.contains(where: { $0.id == actor.id })
        }
        clearSearchSelection()
        await loadMembers(for: list, account: account, appPassword: appPassword, using: client)
        onMembersChanged()
    }

    /// Removes all selected members from the list.
    func bulkRemoveSelectedMembers(
        account: AppAccount,
        appPassword: String,
        using client: LiveBlueskyClient
    ) async {
        let selectedMembers = members.filter { selectedMemberIDs.contains($0.id) }
        guard !selectedMembers.isEmpty else { return }

        let result = await performActorBatch(
            title: "Removing members",
            actors: selectedMembers.map(\.actor),
            operation: .remove,
            addingActorState: false,
            removingMemberIDsByActorDID: Dictionary(
                uniqueKeysWithValues: selectedMembers.map { ($0.actor.did, $0.id) }
            )
        ) { actor in
            guard let member = selectedMembers.first(where: { $0.actor.did == actor.did }) else {
                throw BlueskyAPIError.invalidResponse
            }

            try await client.removeMember(
                recordURI: member.recordURI,
                account: account,
                appPassword: appPassword
            )
        }

        let removedDIDs = Set(result.succeededActors.map(\.did))
        let removedIDs = Set(selectedMembers.filter { removedDIDs.contains($0.actor.did) }.map(\.id))
        members.removeAll { removedIDs.contains($0.id) }
        selectedMemberIDs.subtract(removedIDs)
        onMembersChanged()
        bulkActionResult = result
    }

    /// Blocks all selected members.
    func bulkBlockSelectedMembers(
        account: AppAccount,
        appPassword: String,
        using client: LiveBlueskyClient
    ) async {
        let selectedMembers = members.filter { selectedMemberIDs.contains($0.id) }
        guard !selectedMembers.isEmpty else { return }

        let result = await performActorBatch(
            title: "Blocking members",
            actors: selectedMembers.map(\.actor),
            operation: .block
        ) { actor in
            try await client.blockActor(
                did: actor.did,
                account: account,
                appPassword: appPassword
            )
        }

        clearMemberSelection()
        bulkActionResult = result
    }

    /// Mutes all selected members.
    func bulkMuteSelectedMembers(
        account: AppAccount,
        appPassword: String,
        using client: LiveBlueskyClient
    ) async {
        let selectedMembers = members.filter { selectedMemberIDs.contains($0.id) }
        guard !selectedMembers.isEmpty else { return }

        let result = await performActorBatch(
            title: "Muting members",
            actors: selectedMembers.map(\.actor),
            operation: .mute
        ) { actor in
            try await client.muteActor(
                did: actor.did,
                account: account,
                appPassword: appPassword
            )
        }

        clearMemberSelection()
        bulkActionResult = result
    }

    /// Unblocks all selected members.
    func bulkUnblockSelectedMembers(
        account: AppAccount,
        appPassword: String,
        using client: LiveBlueskyClient
    ) async {
        let selectedMembers = members.filter { selectedMemberIDs.contains($0.id) }
        guard !selectedMembers.isEmpty else { return }

        let result = await performActorBatch(
            title: "Unblocking members",
            actors: selectedMembers.map(\.actor),
            operation: .unblock
        ) { actor in
            let inspection = try await client.inspectProfile(query: actor.did, account: account, appPassword: appPassword)
            if let recordURI = inspection.profile.viewerState?.blockingRecordURI {
                try await client.unblockActor(recordURI: recordURI, account: account, appPassword: appPassword)
            }
        }

        clearMemberSelection()
        bulkActionResult = result
    }

    /// Unmutes all selected members.
    func bulkUnmuteSelectedMembers(
        account: AppAccount,
        appPassword: String,
        using client: LiveBlueskyClient
    ) async {
        let selectedMembers = members.filter { selectedMemberIDs.contains($0.id) }
        guard !selectedMembers.isEmpty else { return }

        let result = await performActorBatch(
            title: "Unmuting members",
            actors: selectedMembers.map(\.actor),
            operation: .unmute
        ) { actor in
            try await client.unmuteActor(
                did: actor.did,
                account: account,
                appPassword: appPassword
            )
        }

        clearMemberSelection()
        bulkActionResult = result
    }

    /// Adds all actors selected in the comparison report to the target list.
    func bulkAddComparisonSelection(
        to list: BlueskyList,
        account: AppAccount,
        appPassword: String,
        using client: LiveBlueskyClient
    ) async {
        let actors = selectedComparisonMembers().map(\.actor)
        guard !actors.isEmpty else { return }

        let result = await performActorBatch(
            title: "Adding comparison results",
            actors: actors,
            operation: .copy
        ) { actor in
            _ = try await client.addActor(
                did: actor.did,
                to: list,
                account: account,
                appPassword: appPassword
            )
        }

        bulkActionResult = result
        selectedComparisonActorDIDs.subtract(result.succeededActors.map(\.did))
        await loadMembers(for: list, account: account, appPassword: appPassword, using: client)
        onMembersChanged()
    }

    /// Transfers (moves or copies) selected members to another list.
    /// - Parameter move: If true, members are removed from the source list after adding to the target.
    func transferSelectedMembers(
        from _: BlueskyList,
        to targetList: BlueskyList,
        move: Bool,
        account: AppAccount,
        appPassword: String,
        using client: LiveBlueskyClient
    ) async {
        let selectedMembers = members.filter { selectedMemberIDs.contains($0.id) }
        guard !selectedMembers.isEmpty else { return }

        let result = await performActorBatch(
            title: move ? "Moving members" : "Copying members",
            actors: selectedMembers.map(\.actor),
            operation: move ? .move : .copy
        ) { actor in
            _ = try await client.addActor(
                did: actor.did,
                to: targetList,
                account: account,
                appPassword: appPassword
            )

            if move, let member = selectedMembers.first(where: { $0.actor.did == actor.did }) {
                try await client.removeMember(
                    recordURI: member.recordURI,
                    account: account,
                    appPassword: appPassword
                )
            }
        }

        if move {
            let removedDIDs = Set(result.succeededActors.map(\.did))
            let removedIDs = Set(selectedMembers.filter { removedDIDs.contains($0.actor.did) }.map(\.id))
            members.removeAll { removedIDs.contains($0.id) }
            selectedMemberIDs.subtract(removedIDs)
            onMembersChanged()
        }

        bulkActionResult = result
    }

    /// Retries all actors that failed in a previous bulk action.
    func retryFailures(
        from result: ListBulkActionResult,
        currentList: BlueskyList,
        comparisonList: BlueskyList?,
        account: AppAccount,
        appPassword: String,
        using client: LiveBlueskyClient
    ) async {
        let failedActors = result.failures.map(\.actor)
        guard !failedActors.isEmpty else { return }

        switch result.operation {
        case .add, .import:
            let retryResult = await performActorBatch(
                title: "Retrying \(result.operation.title.lowercased())",
                actors: failedActors,
                operation: result.operation
            ) { actor in
                _ = try await client.addActor(
                    did: actor.did,
                    to: currentList,
                    account: account,
                    appPassword: appPassword
                )
            }
            bulkActionResult = retryResult
            await loadMembers(for: currentList, account: account, appPassword: appPassword, using: client)
            onMembersChanged()

        case .remove:
            let failedMembers = members.filter { member in
                failedActors.contains(where: { $0.did == member.actor.did })
            }
            let retryResult = await performActorBatch(
                title: "Retrying removals",
                actors: failedMembers.map(\.actor),
                operation: .remove,
                addingActorState: false,
                removingMemberIDsByActorDID: Dictionary(
                    uniqueKeysWithValues: failedMembers.map { ($0.actor.did, $0.id) }
                )
            ) { actor in
                guard let member = failedMembers.first(where: { $0.actor.did == actor.did }) else {
                    throw BlueskyAPIError.invalidResponse
                }
                try await client.removeMember(
                    recordURI: member.recordURI,
                    account: account,
                    appPassword: appPassword
                )
            }
            let removedDIDs = Set(retryResult.succeededActors.map(\.did))
            let removedIDs = Set(failedMembers.filter { removedDIDs.contains($0.actor.did) }.map(\.id))
            members.removeAll { removedDIDs.contains($0.actor.did) }
            selectedMemberIDs.subtract(removedIDs)
            onMembersChanged()
            bulkActionResult = retryResult

        case .block:
            let retryResult = await performActorBatch(
                title: "Retrying blocks",
                actors: failedActors,
                operation: .block
            ) { actor in
                try await client.blockActor(
                    did: actor.did,
                    account: account,
                    appPassword: appPassword
                )
            }
            bulkActionResult = retryResult

        case .mute:
            let retryResult = await performActorBatch(
                title: "Retrying mutes",
                actors: failedActors,
                operation: .mute
            ) { actor in
                try await client.muteActor(
                    did: actor.did,
                    account: account,
                    appPassword: appPassword
                )
            }
            bulkActionResult = retryResult

        case .unblock:
            let retryResult = await performActorBatch(
                title: "Retrying unblocks",
                actors: failedActors,
                operation: .unblock
            ) { actor in
                let inspection = try await client.inspectProfile(query: actor.did, account: account, appPassword: appPassword)
                if let recordURI = inspection.profile.viewerState?.blockingRecordURI {
                    try await client.unblockActor(recordURI: recordURI, account: account, appPassword: appPassword)
                }
            }
            bulkActionResult = retryResult

        case .unmute:
            let retryResult = await performActorBatch(
                title: "Retrying unmutes",
                actors: failedActors,
                operation: .unmute
            ) { actor in
                try await client.unmuteActor(
                    did: actor.did,
                    account: account,
                    appPassword: appPassword
                )
            }
            bulkActionResult = retryResult

        case .report:
            errorMessage = "Cannot retry reports automatically."

        case .copy, .move:
            guard let comparisonList else {
                errorMessage = "Select a comparison list before retrying this action."
                return
            }
            let failedMembers = members.filter { member in
                failedActors.contains(where: { $0.did == member.actor.did })
            }
            let retryResult = await performActorBatch(
                title: "Retrying \(result.operation.title.lowercased())",
                actors: failedActors,
                operation: result.operation,
                removingMemberIDsByActorDID: result.operation == .move
                    ? Dictionary(
                        uniqueKeysWithValues: failedMembers
                            .map { ($0.actor.did, $0.id) }
                    )
                    : [:]
            ) { [self] actor in
                _ = try await client.addActor(
                    did: actor.did,
                    to: comparisonList,
                    account: account,
                    appPassword: appPassword
                )

                if result.operation == .move,
                   let member = members.first(where: { $0.actor.did == actor.did })
                {
                    try await client.removeMember(
                        recordURI: member.recordURI,
                        account: account,
                        appPassword: appPassword
                    )
                }
            }
            if result.operation == .move {
                let movedDIDs = Set(retryResult.succeededActors.map(\.did))
                let movedIDs = Set(members.filter { movedDIDs.contains($0.actor.did) }.map(\.id))
                members.removeAll { movedDIDs.contains($0.actor.did) }
                selectedMemberIDs.subtract(movedIDs)
                onMembersChanged()
            }
            bulkActionResult = retryResult
        }
    }

    // MARK: - Batch Execution

    /// Executes an async action for each actor in the batch with progress and cancellation support.
    func performActorBatch(
        title: String,
        actors: [BlueskyActor],
        operation: ListBulkActionResult.Operation,
        addingActorState: Bool = true,
        removingMemberIDsByActorDID: [String: String] = [:],
        action: @escaping (BlueskyActor) async throws -> Void
    ) async -> ListBulkActionResult {
        let state = batchProgressState
        state.resetBatchCancellation()
        state.isPerformingBulkAction = true
        if addingActorState {
            for actor in actors {
                state.addingActorIDs.insert(actor.did)
            }
        }
        for (_, memberID) in removingMemberIDsByActorDID {
            state.removingMemberIDs.insert(memberID)
        }
        defer {
            state.isPerformingBulkAction = false
            state.batchProgress = nil
            state.addingActorIDs.removeAll()
            state.removingMemberIDs.removeAll()
        }

        return await batchController.performBatch(
            title: title,
            actors: actors,
            operation: operation,
            onProgress: { progress in
                state.batchProgress = progress
            },
            onActorComplete: { actor in
                if addingActorState {
                    state.addingActorIDs.remove(actor.did)
                }
                if let memberID = removingMemberIDsByActorDID[actor.did] {
                    state.removingMemberIDs.remove(memberID)
                }
            },
            isCancelled: { state.isBatchCancelled },
            action: action
        )
    }
}
