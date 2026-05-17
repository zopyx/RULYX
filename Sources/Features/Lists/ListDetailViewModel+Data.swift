import Foundation

extension ListDetailViewModel {
    var loadedMemberSummary: String {
        if hasMoreMembers {
            return "Loaded \(members.count) members so far."
        }

        return "\(members.count) member\(members.count == 1 ? "" : "s") loaded."
    }

    func loadMembers(
        for list: BlueskyList,
        account: AppAccount,
        appPassword: String,
        using client: LiveBlueskyClient
    ) async {
        let start = CFAbsoluteTimeGetCurrent()
        isLoadingMembers = true
        membersErrorMessage = nil
        membersController.reset()
        hasMoreMembers = false

        do {
            members = try await membersController.loadMembers(
                for: list,
                account: account,
                appPassword: appPassword,
                using: client
            )
            hasMoreMembers = membersController.hasMore
            onMembersChanged()
            refreshSearchMembershipFilter()
        } catch {
            membersErrorMessage = AppError.userMessage(from: error)
            members = []
        }

        AppLogger.performance.debug("loadMembers for '\(list.name, privacy: .public)' took \(CFAbsoluteTimeGetCurrent() - start, format: .fixed(precision: 2))s")
        isLoadingMembers = false
    }

    func loadMoreMembersIfNeeded(
        currentMember: BlueskyListMember?,
        list: BlueskyList,
        account: AppAccount,
        appPassword: String,
        using client: LiveBlueskyClient
    ) async {
        guard let currentMember,
              hasMoreMembers,
              !isLoadingMembers,
              !isLoadingMoreMembers,
              currentMember.id == members.suffix(5).first?.id || members.suffix(5).contains(currentMember)
        else {
            return
        }

        isLoadingMoreMembers = true
        defer { isLoadingMoreMembers = false }

        do {
            let newMembers = try await membersController.loadMoreMembers(
                for: list,
                account: account,
                appPassword: appPassword,
                using: client
            )
            members.append(contentsOf: newMembers)
            hasMoreMembers = membersController.hasMore
            onMembersChanged()
        } catch {
            membersErrorMessage = AppError.userMessage(from: error)
        }
    }

    func loadAvailableLists(
        excluding currentList: BlueskyList,
        account: AppAccount,
        appPassword: String,
        using client: LiveBlueskyClient
    ) async {
        isLoadingAvailableLists = true

        do {
            let lists = try await client.fetchLists(for: account, appPassword: appPassword)
            availableLists = lists.filter { $0.id != currentList.id }
                .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        } catch {
            errorMessage = AppError.userMessage(from: error)
            availableLists = []
        }

        isLoadingAvailableLists = false
    }

    func updateMemberFilter(_ query: String) {
        currentMemberFilterQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        recomputeFilteredMembers()
    }

    func recomputeFilteredMembers() {
        let trimmed = currentMemberFilterQuery.lowercased()
        guard !trimmed.isEmpty else {
            filteredMembers = members
            return
        }
        filteredMembers = members.filter {
            $0.actor.handle.lowercased().contains(trimmed) ||
                ($0.actor.displayName?.lowercased().contains(trimmed) ?? false)
        }
    }

    func onMembersChanged() {
        selectedMemberIDs = selectedMemberIDs.intersection(Set(members.map(\.id)))
        recomputeFilteredMembers()
    }

    func prepareImportPreview(
        from rawInput: String,
        sourceDescription: String,
        account: AppAccount,
        appPassword: String,
        using client: LiveBlueskyClient
    ) async {
        isPreparingImportPreview = true
        defer { isPreparingImportPreview = false }

        do {
            let existingDIDs = Set(members.map(\.actor.did))
            importPreview = try await importController.preparePreview(
                from: rawInput,
                sourceDescription: sourceDescription,
                existingMemberDIDs: existingDIDs,
                account: account,
                appPassword: appPassword,
                using: client
            )
        } catch {
            errorMessage = AppError.userMessage(from: error)
        }
    }

    func commitImportPreview(
        to list: BlueskyList,
        account: AppAccount,
        appPassword: String,
        using client: LiveBlueskyClient
    ) async {
        guard let importPreview else { return }

        let actorsToImport = importPreview.items.compactMap { item -> BlueskyActor? in
            switch item.classification {
            case .ready:
                return item.actor
            case .alreadyPresent:
                return nil
            case .duplicate, .unresolved:
                return nil
            }
        }

        guard !actorsToImport.isEmpty else {
            errorMessage = "Nothing is eligible for import."
            return
        }

        isImportingHandles = true
        let result = await performActorBatch(
            title: "Importing handles",
            actors: actorsToImport,
            operation: .import
        ) { actor in
            _ = try await client.addActor(
                did: actor.did,
                to: list,
                account: account,
                appPassword: appPassword
            )
        }
        isImportingHandles = false
        bulkActionResult = result
        self.importPreview = nil
        await loadMembers(for: list, account: account, appPassword: appPassword, using: client)
        onMembersChanged()
    }

    func discardImportPreview() {
        importPreview = nil
    }

    func compare(
        currentList: BlueskyList,
        otherList: BlueskyList,
        account: AppAccount,
        appPassword: String,
        using client: LiveBlueskyClient
    ) async {
        let start = CFAbsoluteTimeGetCurrent()
        isComparingLists = true
        defer { isComparingLists = false }

        do {
            comparisonReport = try await diffController.compare(
                currentMembers: members,
                otherList: otherList,
                account: account,
                appPassword: appPassword,
                using: client
            )
            selectedComparisonActorDIDs = []
        } catch {
            errorMessage = AppError.userMessage(from: error)
            comparisonReport = nil
            selectedComparisonActorDIDs = []
        }

        AppLogger.performance.debug("compare for '\(currentList.name, privacy: .public)' took \(CFAbsoluteTimeGetCurrent() - start, format: .fixed(precision: 2))s")
    }

    func clearComparison() {
        comparisonReport = nil
        selectedComparisonActorDIDs = []
    }

    func comparisonMembers(for bucket: ComparisonBucket) -> [BlueskyListMember] {
        guard let comparisonReport else { return [] }
        return diffController.comparisonMembers(for: bucket, in: comparisonReport)
    }

    func selectedComparisonMembers() -> [BlueskyListMember] {
        guard let comparisonReport else { return [] }
        return diffController.selectedComparisonMembers(
            selectedDIDs: selectedComparisonActorDIDs,
            in: comparisonReport
        )
    }

    func exportRows() -> [String] {
        members.map { member in
            [
                member.actor.handle.csvField,
                member.actor.did.csvField,
                (member.actor.displayName ?? "").csvField,
            ].joined(separator: ",")
        }
    }

    func exportDiffRows() -> [String] {
        guard let comparisonReport else { return [] }
        return diffController.exportDiffRows(from: comparisonReport)
    }

    func updateMetadata(
        for list: BlueskyList,
        title: String,
        description: String,
        account: AppAccount,
        appPassword: String,
        using client: LiveBlueskyClient
    ) async -> BlueskyList? {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedDescription = description.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedTitle.isEmpty else {
            errorMessage = "List title is required."
            return nil
        }

        isUpdatingMetadata = true
        defer { isUpdatingMetadata = false }

        do {
            let updatedList = try await client.updateListMetadata(
                list: list,
                title: trimmedTitle,
                description: trimmedDescription,
                account: account,
                appPassword: appPassword
            )
            errorMessage = nil
            return updatedList
        } catch {
            errorMessage = AppError.userMessage(from: error)
            return nil
        }
    }
}
