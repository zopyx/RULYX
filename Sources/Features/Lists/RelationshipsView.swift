import SwiftUI

// MARK: - RelationshipMode

/// The type of relationship list to display.
enum RelationshipMode: String, CaseIterable {
    case followers
    case following
    case blocking
    case blockedBy

    /// User-facing title for this relationship mode.
    var title: String {
        switch self {
        case .followers: "My followers"
        case .following: "My followings"
        case .blocking: "Blocking"
        case .blockedBy: "Blocked by"
        }
    }

    /// Returns the title with a count suffix.
    func titled(_ count: Int) -> String {
        "\(title) (\(count))"
    }
}

// MARK: - RelationshipsView

/// Displays a list of actors for a given relationship (followers, following,
/// blocking, blocked by) with search, export, block, and add-to-list actions.
struct RelationshipsView: View {
    let mode: RelationshipMode
    let initialCount: Int?
    var profileDID: String?
    var profileHandle: String?
    @EnvironmentObject private var accountStore: AccountStore
    @EnvironmentObject private var blueskyClient: LiveBlueskyClient
    @EnvironmentObject private var localizationManager: LocalizationManager
    @EnvironmentObject private var internalListStore: InternalListStore
    @AppStorage("debugMode") private var debugMode = false
    @State private var actors: [BlueskyActor] = []
    @State private var isLoading = true
    @State private var isRefreshing = false
    @State private var searchQuery = ""
    @State private var errorMessage: String?
    @State private var statusMessage: String?
    @State private var selectedActorForList: BlueskyActor?
    @State private var isShowingListPicker = false
    @State private var isShowingBlockConfirm = false
    @State private var actorToBlock: BlueskyActor?
    @State private var shareFileURL: URL?
    @State private var isExporting = false
    @State private var exportProgressMessage: String?
    @State private var exportProgressFraction: Double?
    @State private var clearskyTotal: Int?
    @State private var availableTargetLists: [BlueskyList] = []
    @State private var batchOperationConfig: BatchOperationConfig?

    // Block-all-back state
    @State private var isBlockingBack = false
    @State private var blockBackCompleted = 0
    @State private var blockBackTotal = 0
    @State private var blockBackSuccessCount = 0
    @State private var blockBackFailureCount = 0
    @State private var showBlockBackConfirm1 = false
    @State private var showBlockBackConfirm2 = false
    @State private var unblockedBlockersCount: Int?
    @State private var showBlockBackAllClear = false

    /// Filters actors by handle or display name matching the search query.
    private var filteredActors: [BlueskyActor] {
        let trimmed = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return actors }
        return actors.filter {
            $0.handle.lowercased().contains(trimmed) ||
                ($0.displayName?.lowercased().contains(trimmed) ?? false)
        }
    }

    /// Localized title for the current mode, optionally including a profile handle.
    private var modeLocalized: String {
        if let handle = profileHandle {
            switch mode {
            case .followers: return String.localized("rel.mode.followers_of", replacements: ["handle": handle])
            case .following: return String.localized("rel.mode.following_of", replacements: ["handle": handle])
            case .blocking: return String.localized("rel.mode.blocking")
            case .blockedBy: return String.localized("rel.mode.blocked_by")
            }
        }
        switch mode {
        case .followers: return String.localized("rel.mode.followers")
        case .following: return String.localized("rel.mode.following")
        case .blocking: return String.localized("rel.mode.blocking")
        case .blockedBy: return String.localized("rel.mode.blocked_by")
        }
    }

    // MARK: - Body

    var body: some View {
        Group {
            if isLoading {
                ProgressView(String.localized("rel.loading", replacements: ["mode": modeLocalized.lowercased()]))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let errorMessage {
                ErrorRetryBanner(message: errorMessage) {
                    Task { await load() }
                }
            } else {
                List {
                    if !actors.isEmpty {
                        Section {
                            TextField(String.localized("rel.search_placeholder", replacements: ["mode": modeLocalized.lowercased()]), text: $searchQuery)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                            if let statusMessage {
                                Text(statusMessage)
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }

                    if filteredActors.isEmpty, !isLoading {
                        ContentUnavailableView {
                            Label(modeLocalized, systemImage: "person.3")
                        } description: {
                            Text(searchQuery.isEmpty ? String.localized("rel.no_accounts") : String.localized("rel.no_matches"))
                        }
                    } else {
                        ForEach(Array(filteredActors.enumerated()), id: \.element.id) { index, actor in
                            NavigationLink {
                                BlueskyProfileView(
                                    member: BlueskyListMember(recordURI: "rel:\(actor.did)", actor: actor),
                                    list: nil
                                )
                            } label: {
                                HStack(spacing: 0) {
                                    BlueskyActorRow(actor: actor) {
                                        if actor.isNew {
                                            Text(loc: "rel.new_badge")
                                                .font(.caption2.weight(.semibold))
                                                .foregroundStyle(.orange)
                                                .padding(.horizontal, 5)
                                                .padding(.vertical, 1)
                                                .background(Color.orange.opacity(0.12), in: Capsule())
                                        }
                                        Spacer(minLength: 0)
                                        if let blockedDate = actor.blockedDate {
                                            Text(blockedDateDisplay(blockedDate))
                                                .font(.caption2.weight(.regular))
                                                .foregroundStyle(.primary)
                                        }
                                    }
                                    if debugMode {
                                        Text("\(index + 1)")
                                            .font(.caption2)
                                            .foregroundStyle(.tertiary)
                                    }
                                }
                            }
                            .appScrollTransition()
                            .contextMenu {
                                Button(role: .destructive) {
                                    actorToBlock = actor
                                    isShowingBlockConfirm = true
                                } label: {
                                    Label(loc("rel.block"), systemImage: "hand.raised.fill")
                                }
                                .accessibilityHint(loc: "rel.block.hint")

                                Button {
                                    selectedActorForList = actor
                                    isShowingListPicker = true
                                } label: {
                                    Label(loc("rel.add_to_list"), systemImage: "list.bullet")
                                }
                                .accessibilityHint(loc: "rel.add_to_list.hint")
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button(role: .destructive) {
                                    actorToBlock = actor
                                    isShowingBlockConfirm = true
                                } label: {
                                    Label(loc("rel.block"), systemImage: "hand.raised.fill")
                                }
                                .accessibilityHint(loc: "rel.block_swipe.hint")
                            }
                        }
                        .onDelete { indexSet in
                            if let idx = indexSet.first, idx < filteredActors.count {
                                actorToBlock = filteredActors[idx]
                                isShowingBlockConfirm = true
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .pageTitle("\(modeLocalized) (\(clearskyTotal ?? actors.count))")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 16) {
                    if !actors.isEmpty, mode == .blockedBy {
                        bulkAddToListsMenu
                    }
                    if !actors.isEmpty {
                        Menu {
                            Button {
                                isExporting = true
                                Task { await exportAll(format: .csv) }
                            } label: {
                                Label { Text(loc: "list.search.export_csv_all") } icon: { Image(systemName: "arrow.down.doc") }
                            }

                            Button {
                                isExporting = true
                                Task { await exportAll(format: .json) }
                            } label: {
                                Label { Text(loc: "list.search.export_json_all") } icon: { Image(systemName: "arrow.down.doc") }
                            }

                            Button {
                                isExporting = true
                                Task { await exportAll(format: .xlsx) }
                            } label: {
                                Label { Text(loc: "list.export.excel") } icon: { Image(systemName: "arrow.down.doc") }
                            }

                            Button {
                                isExporting = true
                                Task { await exportAll(format: .ods) }
                            } label: {
                                Label { Text(loc: "list.export.ods") } icon: { Image(systemName: "arrow.down.doc") }
                            }
                        } label: {
                            if isExporting {
                                HStack(spacing: 6) {
                                    if let fraction = exportProgressFraction {
                                        ProgressView(value: fraction)
                                            .frame(width: 40)
                                            .scaleEffect(x: 1, y: 0.6)
                                    } else {
                                        ProgressView()
                                            .scaleEffect(0.8)
                                    }
                                    if let msg = exportProgressMessage {
                                        Text(msg)
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            } else {
                                Image(systemName: "arrow.down.doc")
                            }
                        }
                        .disabled(isExporting)
                    }
                }
            }
        }
        .refreshable {
            await refresh()
        }
        .task(id: accountStore.activeAccountID) {
            await load()
        }
        .confirmationDialog(
            String.localized("rel.block_confirm"),
            isPresented: $isShowingBlockConfirm,
            titleVisibility: .visible
        ) {
            Button(String.localized("rel.block"), role: .destructive) {
                guard let actor = actorToBlock,
                      let account = accountStore.activeAccount,
                      let appPassword = accountStore.appPassword(for: account) else { return }
                Task {
                    do {
                        try await blueskyClient.blockActor(
                            did: actor.did,
                            account: account,
                            appPassword: appPassword
                        )
                        actors.removeAll { $0.did == actor.did }
                    } catch {
                        errorMessage = AppError.userMessage(from: error)
                    }
                }
            }
            .accessibilityInputLabels([loc("rel.block")])
            Button(String.localized("actions.cancel"), role: .cancel) {}
                .accessibilityInputLabels([loc("actions.cancel")])

            Text(loc: "rel.block_message")
        }
        .alert(Text(loc: "profile.block_back.confirm.first.title"), isPresented: $showBlockBackConfirm1) {
            Button(loc("actions.cancel"), role: .cancel) {}
            Button(loc("profile.block_back.action")) {
                showBlockBackConfirm2 = true
            }
        } message: {
            if let count = unblockedBlockersCount {
                Text(loc("profile.block_back.confirm.first.message").replacingOccurrences(of: "{count}", with: "\(count)"))
            }
        }
        .alert(Text(loc: "profile.block_back.confirm.second.title"), isPresented: $showBlockBackConfirm2) {
            Button(loc("actions.cancel"), role: .cancel) {}
            Button(loc("profile.block_back.action"), role: .destructive) {
                if let account = accountStore.activeAccount,
                   let appPassword = accountStore.appPassword(for: account) {
                    Task {
                        await blockBack(account: account, appPassword: appPassword)
                    }
                }
            }
        } message: {
            if let count = unblockedBlockersCount {
                Text(loc("profile.block_back.confirm.second.message").replacingOccurrences(of: "{count}", with: "\(count)"))
            }
        }
        .alert(loc("profile.block_back.all_clear"), isPresented: $showBlockBackAllClear) {
            Button(loc("actions.ok"), role: .cancel) {}
        }
        .sheet(isPresented: $isShowingListPicker) {
            if let actor = selectedActorForList,
               let account = accountStore.activeAccount,
               let appPassword = accountStore.appPassword(for: account)
            {
                ListPickerSheet(actor: actor, account: account, appPassword: appPassword, client: blueskyClient)
                    .environmentObject(accountStore)
                    .environmentObject(blueskyClient)
            }
        }
        .sheet(isPresented: .init(get: { shareFileURL != nil }, set: { if !$0 { shareFileURL = nil } })) {
            if let url = shareFileURL {
                ShareSheet(activityItems: [url])
            }
        }
        .sheet(item: $batchOperationConfig) { config in
            BatchOperationProgressView(config: config)
                .environmentObject(blueskyClient)
                .environmentObject(localizationManager)
        }
        .task {
            await loadAvailableTargetLists()
        }
    }

    // MARK: - Helpers

    /// Moderation lists available as add-all targets.
    private var moderationTargetLists: [BlueskyList] {
        availableTargetLists.filter { $0.kind == .moderation }
    }

    /// Internal lists available as add-all targets.
    private var internalTargetLists: [BlueskyList] {
        availableTargetLists.filter { $0.kind == .internal }
    }

    /// Regular lists available as add-all targets.
    private var regularTargetLists: [BlueskyList] {
        availableTargetLists.filter { $0.kind == .regular }
    }

    /// Menu button to add all blocked-by actors to a moderation/curation/internal list.
    private var bulkAddToListsMenu: some View {
        Menu {
            if !moderationTargetLists.isEmpty {
                Menu {
                    ForEach(moderationTargetLists) { list in
                        Button {
                            handleAddAllBlockers(to: list)
                        } label: {
                            Label(list.name, systemImage: list.kind.symbolName)
                        }
                    }
                } label: {
                    Text(loc: "rel.add_to_moderation_list")
                }
            }
            if !internalTargetLists.isEmpty {
                Menu {
                    ForEach(internalTargetLists) { list in
                        Button {
                            handleAddAllBlockers(to: list)
                        } label: {
                            Label(list.name, systemImage: list.kind.symbolName)
                        }
                    }
                } label: {
                    Text(loc: "rel.add_to_internal_list")
                }
            }
            if !regularTargetLists.isEmpty {
                Menu {
                    ForEach(regularTargetLists) { list in
                        Button {
                            handleAddAllBlockers(to: list)
                        } label: {
                            Label(list.name, systemImage: list.kind.symbolName)
                        }
                    }
                } label: {
                    Text(loc: "rel.add_to_curation_list")
                }
            }
            if !moderationTargetLists.isEmpty || !internalTargetLists.isEmpty || !regularTargetLists.isEmpty {
                Divider()
            }
            Button {
                Task { await handleBlockAllBack() }
            } label: {
                Label(loc("rel.block_all_back"), systemImage: "hand.raised.slash.fill")
            }
            .disabled(isBlockingBack)
            if availableTargetLists.isEmpty {
                Button {
                    Task { await loadAvailableTargetLists() }
                } label: {
                    Label(loc("rel.loading_lists"), systemImage: "arrow.triangle.2.circlepath")
                }
                .disabled(true)
            }
        } label: {
            Image(systemName: "ellipsis.circle")
        }
        .accessibilityLabel(loc("rel.add_all_to_list"))
        .accessibilityHint(loc("rel.add_all_to_list.hint"))
    }

    /// Handles adding all currently loaded actors to the selected list.
    /// Internal lists get direct member additions; external lists use the batch progress UI.
    private func handleAddAllBlockers(to list: BlueskyList) {
        let targets = actors.map { actor in
            PendingLikerTarget(did: actor.did, handle: actor.handle)
        }
        guard !targets.isEmpty else { return }

        if list.kind == .internal {
            for target in targets {
                internalListStore.addMember(
                    did: target.did,
                    handle: target.handle ?? target.did,
                    to: internalListStore.listID(from: list.id)
                )
            }
        } else {
            guard let account = accountStore.activeAccount,
                  let appPassword = accountStore.appPassword(for: account) else { return }
            batchOperationConfig = BatchOperationConfig(
                targets: targets,
                mode: .addToList(list: list, account: account, appPassword: appPassword)
            )
        }
    }

    /// Fetches the count of unblocked blockers and presents the first confirmation dialog.
    private func handleBlockAllBack() async {
        guard let account = accountStore.activeAccount else { return }
        do {
            let count = try await blueskyClient.fetchUnblockedBlockersCount(for: account)
            unblockedBlockersCount = count
            guard count > 0 else {
                showBlockBackAllClear = true
                return
            }
            showBlockBackConfirm1 = true
        } catch {
            AppLogger.moderation.error("Failed to fetch unblocked blockers count: \\(error.localizedDescription, privacy: .public)")
        }
    }

    /// Executes the block-back operation: fetches unblocked blocker actors and blocks each in batches.
    private func blockBack(account: AppAccount, appPassword: String) async {
        isBlockingBack = true
        blockBackCompleted = 0
        blockBackTotal = 0
        blockBackSuccessCount = 0
        blockBackFailureCount = 0

        do {
            let toBlock = try await blueskyClient.fetchUnblockedBlockerActors(account: account, appPassword: appPassword)

            guard !toBlock.isEmpty else {
                isBlockingBack = false
                return
            }

            blockBackTotal = toBlock.count
            let batchSize = 5

            for batchStart in stride(from: 0, to: blockBackTotal, by: batchSize) {
                let batchEnd = min(batchStart + batchSize, blockBackTotal)
                let batch = toBlock[batchStart ..< batchEnd]

                await withTaskGroup(of: Bool.self) { group in
                    for actor in batch {
                        group.addTask {
                            do {
                                try await blueskyClient.blockActor(did: actor.did, account: account, appPassword: appPassword)
                                return true
                            } catch {
                                AppLogger.moderation.error("Block back failed for \\(actor.handle, privacy: .public): \\(error.localizedDescription, privacy: .public)")
                                return false
                            }
                        }
                    }
                    for await success in group {
                        blockBackCompleted += 1
                        if success {
                            blockBackSuccessCount += 1
                        } else {
                            blockBackFailureCount += 1
                        }
                    }
                }

                if batchEnd < blockBackTotal {
                    try await Task.sleep(for: .milliseconds(300))
                }
            }
        } catch {
            AppLogger.moderation.error("Block back failed: \\(error.localizedDescription, privacy: .public)")
        }

        isBlockingBack = false
    }

    /// Loads the user's moderation, internal, and regular lists for the bulk add-all menu.
    private func loadAvailableTargetLists() async {
        var lists: [BlueskyList] = []
        if let account = accountStore.activeAccount,
           let appPassword = accountStore.appPassword(for: account)
        {
            do {
                lists = try await blueskyClient.fetchLists(for: account, appPassword: appPassword)
            } catch {
                AppLogger.moderation.error("Failed to load available target lists: \\(error.localizedDescription, privacy: .public)")
            }
        }
        let internalLists = internalListStore.lists.map { internalList in
            BlueskyList(
                id: "internal:\\(internalList.id.uuidString)",
                name: internalList.name,
                description: "Internal",
                memberCount: internalList.memberCount,
                kind: .internal,
                cid: nil
            )
        }
        lists.append(contentsOf: internalLists)
        availableTargetLists = lists.sorted { lhs, rhs in
            if lhs.kind != rhs.kind {
                return lhs.kind.sortOrder < rhs.kind.sortOrder
            }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    /// Formats a blocked date as relative (< 30 days) or abbreviated.
    private func blockedDateDisplay(_ date: Date) -> String {
        let days = Calendar.current.dateComponents([.day], from: date, to: .now).day ?? 0
        if days < 30 {
            return date.formatted(.relative(presentation: .named))
        }
        return date.formatted(date: .abbreviated, time: .omitted)
    }

    /// Exports all actors in the requested format with profile stats.
    private func exportAll(format: ExportFormat) async {
        let sanitizedName = mode.rawValue

        let dids = actors.map(\.did)
        _ = (dids.count + 24) / 25
        exportProgressFraction = 0
        let stats = await (try? LiveBlueskyClient.fetchProfileStats(dids: dids) { current, total in
            Task { @MainActor in
                exportProgressFraction = Double(current) / Double(total)
                exportProgressMessage = "Processing... \(current)/\(total)"
            }
        }) ?? [:]

        exportProgressMessage = "Processing..."

        let data: Data

        switch format {
        case .csv:
            let csv = generateCSV(from: actors, stats: stats)
            data = Data(csv.utf8)
        case .json:
            data = generateJSON(from: actors, stats: stats)
        case .xlsx, .ods:
            let headers = ["handle", "did", "display_name", "created_at", "followers", "following", "posts", "description"]
            let rows = actors.map { actor in
                let s = stats[actor.did]
                return [
                    actor.handle,
                    actor.did,
                    actor.displayName ?? "",
                    actor.createdAt?.ISO8601Format() ?? "",
                    "\(s?.followers ?? 0)",
                    "\(s?.following ?? 0)",
                    "\(s?.posts ?? 0)",
                    s?.description ?? "",
                ]
            }
            if format == .xlsx {
                guard let xlsx = SpreadsheetExport.generateXLSX(headers: headers, rows: rows) else {
                    isExporting = false
                    exportProgressMessage = nil
                    return
                }
                data = xlsx
            } else {
                guard let ods = SpreadsheetExport.generateODS(headers: headers, rows: rows) else {
                    isExporting = false
                    exportProgressMessage = nil
                    return
                }
                data = ods
            }
        }

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(sanitizedName)-full-export.\(format.rawValue)")
        try? data.write(to: url, options: .atomic)
        isExporting = false
        exportProgressMessage = nil
        shareFileURL = url
    }

    /// Generates CSV string with handle, DID, display name, dates, and stats.
    private func generateCSV(from actors: [BlueskyActor], stats: [String: (followers: Int, following: Int, posts: Int, description: String)] = [:]) -> String {
        let header = "handle,did,display_name,created_at,followers,following,posts,description"
        let rows = actors.map { actor in
            let s = stats[actor.did]
            return [
                actor.handle.csvField,
                actor.did.csvField,
                (actor.displayName ?? "").csvField,
                (actor.createdAt?.ISO8601Format() ?? "").csvField,
                "\(s?.followers ?? 0)",
                "\(s?.following ?? 0)",
                "\(s?.posts ?? 0)",
                (s?.description ?? "").csvField,
            ].joined(separator: ",")
        }
        return ([header] + rows).joined(separator: "\n")
    }

    /// Generates JSON data with handle, DID, display name, dates, and stats.
    private func generateJSON(from actors: [BlueskyActor], stats: [String: (followers: Int, following: Int, posts: Int, description: String)] = [:]) -> Data {
        let objects = actors.map { actor in
            let s = stats[actor.did]
            return [
                "handle": actor.handle,
                "did": actor.did,
                "display_name": actor.displayName ?? "",
                "created_at": actor.createdAt?.ISO8601Format() ?? "",
                "description": s?.description ?? "",
                "followers": s?.followers ?? 0,
                "following": s?.following ?? 0,
                "posts": s?.posts ?? 0,
            ] as [String: Any]
        }
        return (try? JSONSerialization.data(withJSONObject: objects, options: [.prettyPrinted, .sortedKeys])) ?? Data()
    }

    /// Computes a cache key from the mode and subject DID.
    private var cacheKey: String? {
        guard let accountDID = accountStore.activeAccount?.did else { return nil }
        let subject = profileDID ?? accountDID
        return "\(mode.rawValue)_\(subject)"
    }

    /// Loads cached data first, then fetches fresh data from the API.
    private func load() async {
        guard let account = accountStore.activeAccount,
              let appPassword = accountStore.appPassword(for: account)
        else {
            errorMessage = String.localized("rel.select_account_first")
            isLoading = false
            return
        }

        actors = []
        errorMessage = nil

        let cached: [BlueskyActor] = if let key = cacheKey {
            RelationshipCache.load(forKey: key)
        } else {
            []
        }

        if !cached.isEmpty {
            actors = cached
            isLoading = false
        } else {
            isLoading = true
        }

        await fetchFromAPI(account: account, appPassword: appPassword)
    }

    /// Pull-to-refresh that bypasses cache.
    private func refresh() async {
        guard let account = accountStore.activeAccount,
              let appPassword = accountStore.appPassword(for: account) else { return }
        isRefreshing = true
        await fetchFromAPI(account: account, appPassword: appPassword)
        isRefreshing = false
    }

    /// Fetches actors from the Bluesky/CloudSky API based on mode, then caches the result.
    private func fetchFromAPI(account: AppAccount, appPassword: String) async {
        do {
            let did = profileDID ?? account.did ?? account.handle
            let result: [BlueskyActor]
            switch mode {
            case .followers:
                result = try await blueskyClient.fetchFollowers(actor: did, account: account, appPassword: appPassword)
            case .following:
                result = try await blueskyClient.fetchFollowing(actor: did, account: account, appPassword: appPassword)
            case .blocking:
                let r = try await blueskyClient.fetchBlockedActors(account: account, appPassword: appPassword)
                result = r.actors
                clearskyTotal = r.totalCount
            case .blockedBy:
                let r = try await blueskyClient.fetchBlockedByActors(account: account, appPassword: appPassword)
                result = r.actors
                clearskyTotal = r.totalCount
            }
            if mode == .blocking || mode == .blockedBy {
                actors = result.sorted { ($0.blockedDate ?? .distantPast) > ($1.blockedDate ?? .distantPast) }
            } else {
                actors = result
            }
            isLoading = false
            if let key = cacheKey {
                RelationshipCache.save(actors, forKey: key)
            }
        } catch {
            if actors.isEmpty {
                errorMessage = AppError.userMessage(from: error)
                isLoading = false
            } else {
                statusMessage = String.localized("rel.loaded_status", replacements: ["count": "\(actors.count)", "total": "\(initialCount ?? actors.count)"])
            }
        }
    }
}

// MARK: - ExportFormat

private enum ExportFormat: String, CaseIterable {
    case csv, json, xlsx, ods
}

// MARK: - ShareSheet

private struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context _: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_: UIActivityViewController, context _: Context) {}
}

// MARK: - ListPickerSheet

/// Sheet for picking a list to add an actor to.
struct ListPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    let actor: BlueskyActor
    let account: AppAccount
    let appPassword: String
    let client: LiveBlueskyClient
    @State private var lists: [BlueskyList] = []
    @State private var isLoading = true

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView(loc("rel.loading_lists"))
                } else if lists.isEmpty {
                    ContentUnavailableView(loc("rel.no_lists_title"), systemImage: "tray", description: Text(loc: "rel.no_lists_desc"))
                } else {
                    List(lists) { list in
                        Button {
                            Task {
                                do {
                                    _ = try await client.addActor(did: actor.did, to: list, account: account, appPassword: appPassword)
                                    dismiss()
                                } catch {}
                            }
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(list.name)
                                    Text(list.kind.title)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "plus.circle")
                                    .foregroundStyle(Color.skyPrimary)
                            }
                        }
                        .accessibilityHint(loc: "rel.added_to_list.hint")
                    }
                }
            }
            .pageTitle("\(String.localized("rel.add_to_list")) \(actor.handle)")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(loc("actions.cancel")) { dismiss() }
                        .accessibilityHint(loc: "rel.close_picker.hint")
                }
            }
            .task {
                do {
                    lists = try await client.fetchLists(for: account, appPassword: appPassword)
                } catch {}
                isLoading = false
            }
        }
        .presentationDetents([.medium, .large])
    }
}
