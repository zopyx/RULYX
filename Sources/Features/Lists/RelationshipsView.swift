import Observation
import SwiftUI
import UniformTypeIdentifiers

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
    var onCountUpdate: ((RelationshipMode, Int) -> Void)?
    var profileDID: String?
    var profileHandle: String?
    @EnvironmentObject private var accountStore: AccountStore
    @EnvironmentObject private var container: BlueskyServiceContainerWrapper
    @EnvironmentObject private var localizationManager: LocalizationManager
    @EnvironmentObject private var internalListStore: InternalListStore
    @AppStorage("debugMode") private var debugMode = false
    @AppStorage("showDangerousOperations") private var showDangerousOperations = false
    @AppStorage("showActorDescriptions") private var showActorDescriptions = false
    @AppStorage("showActorStats") private var showActorStats = false
    @AppStorage("confirmBlocks") private var confirmBlocks = true
    @State private var actors: [BlueskyActor] = []
    @State private var isLoading = true
    @State private var isRefreshing = false
    @State private var searchQuery = ""
    @State private var errorMessage: String?
    @State private var statusMessage: String?
    @State private var profileStats: [String: (followers: Int, following: Int, posts: Int, description: String)] = [:]
    @State private var isLoadingStats = false
    @State private var filterNoPosts = false
    @State private var showBlockNoPostsConfirm = false
    @State private var blockNoPostsCount = 0
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
    @State private var listsLoaded = false
    @State private var isShowingJSONImportPicker = false
    @State private var importedJSONTargets: [PendingLikerTarget] = []
    @State private var isChoosingJSONImportList = false
    @State private var jsonImportError: String?

    /// DID → block record URI for unblocking (Blocking mode). Only populated when mode == .blocking.
    @State private var blockRecordURIs: [String: String] = [:]

    // MARK: - Multi-Select State

    /// Whether the view is in multi-select mode (checkbox + bulk actions).
    @State private var isSelectMode = false
    /// Set of DIDs selected by the user in multi-select mode.
    @State private var selectedDIDs: Set<String> = []
    /// Show confirmation dialog before executing bulk block on selected actors.
    @State private var showBulkBlockConfirm = false

    /// The actors currently selected (derived from selectedDIDs).
    private var selectedActors: [BlueskyActor] {
        actors.filter { selectedDIDs.contains($0.did) }
    }

    /// Renders an actor row with optional checkbox in multi-select mode.
    @ViewBuilder
    private func selectableActorRow(actor: BlueskyActor, index: Int) -> some View {
        if isSelectMode {
            HStack(spacing: 12) {
                Image(systemName: selectedDIDs.contains(actor.did) ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(selectedDIDs.contains(actor.did) ? Color.skyPrimary : Color.secondary)
                    .font(.title2)
                actorRowLabel(actor: actor, index: index)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                if selectedDIDs.contains(actor.did) {
                    selectedDIDs.remove(actor.did)
                } else {
                    selectedDIDs.insert(actor.did)
                }
            }
        } else {
            actorRowLabel(actor: actor, index: index)
                .contentShape(Rectangle())
                .onTapGesture(count: 2) {
                    Task { await toggleFollow(actor: actor) }
                }
                .onTapGesture(count: 1) {
                    selectedActor = actor
                }
        }
    }

    /// Actor selected for profile navigation (single tap).
    @State private var selectedActor: BlueskyActor?

    // MARK: - Optimistic Follow State (double-tap)

    /// DIDs for which the user has double-tapped to follow (optimistic).
    @State private var pendingFollowActions: Set<String> = []
    /// DIDs for which the user has double-tapped to unfollow (optimistic).
    @State private var pendingUnfollowActions: Set<String> = []
    /// Follow record URIs captured from successful follow calls (needed for unfollow before next API reload).
    @State private var optimisticFollowRecordURIs: [String: String] = [:]

    /// Block-all-back state — uses shared VM
    @State private var actionsVM: BlueskyProfileActionsViewModel?

    private func wireActionsVM() {
        let vm = actionsVM ?? {
            let v = BlueskyProfileActionsViewModel(
                profileService: container.blueskyClient,
                clearskyService: container.blueskyClient,
                accountStore: accountStore
            )
            v.resultDisplayDuration = 0 // fast transition in list view
            actionsVM = v
            return v
        }()
        // Ensure dependencies are current (safe to call if already wired)
        vm.reconfigure(
            profileService: container.blueskyClient,
            clearskyService: container.blueskyClient,
            accountStore: accountStore
        )
    }

    @State private var showBlockBackConfirm1 = false
    @State private var showBlockBackConfirm2 = false
    @State private var showBlockBackAllClear = false

    /// Filters actors by handle or display name matching the search query,
    /// and optionally by no-posts filter for following mode.
    private var filteredActors: [BlueskyActor] {
        let trimmed = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        var result = actors
        if !trimmed.isEmpty {
            result = result.filter {
                $0.handle.lowercased().contains(trimmed) ||
                    ($0.displayName?.lowercased().contains(trimmed) ?? false)
            }
        }
        if mode == .following, filterNoPosts {
            result = result.filter { actor in
                guard let stats = profileStats[actor.did] else { return false }
                return stats.posts == 0
            }
        }
        return result
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
                            if mode == .following {
                                Toggle(isOn: $filterNoPosts) {
                                    HStack(spacing: 6) {
                                        Image(systemName: "text.badge.minus")
                                            .foregroundStyle(.secondary)
                                        Text(loc: "rel.filter_no_posts")
                                    }
                                }
                                .disabled(isLoadingStats || profileStats.isEmpty)
                                .toggleStyle(.switch)
                            }
                            if let statusMessage {
                                Text(statusMessage)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
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
                            selectableActorRow(actor: actor, index: index)
                                .appScrollTransition()
                                .contextMenu {
                                    Button(role: .destructive) {
                                        actorToBlock = actor
                                        if confirmBlocks {
                                            isShowingBlockConfirm = true
                                        } else {
                                            performBlock(actor)
                                        }
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
                                    if mode == .blocking {
                                        Button {
                                            performUnblock(actor)
                                        } label: {
                                            Label(loc("rel.unblock"), systemImage: "lock.open.fill")
                                        }
                                        .tint(.orange)
                                        .accessibilityHint(loc: "rel.unblock.hint")
                                    } else {
                                        Button(role: .destructive) {
                                            actorToBlock = actor
                                            if confirmBlocks {
                                                isShowingBlockConfirm = true
                                            } else {
                                                performBlock(actor)
                                            }
                                        } label: {
                                            Label(loc("rel.block"), systemImage: "hand.raised.fill")
                                        }
                                        .accessibilityHint(loc: "rel.block_swipe.hint")
                                    }
                                }
                                .swipeActions(edge: .leading, allowsFullSwipe: false) {
                                    if mode == .followers {
                                        Button {
                                            performForceUnfollow(actor)
                                        } label: {
                                            Label(loc("rel.force_unfollow"), systemImage: "person.crop.circle.badge.minus")
                                        }
                                        .tint(.orange)
                                        .accessibilityHint(loc: "rel.force_unfollow.hint")
                                    } else if mode == .following {
                                        Button {
                                            performForceUnfollow(actor)
                                        } label: {
                                            Label(loc("rel.unfollow"), systemImage: "person.fill.xmark")
                                        }
                                        .tint(.orange)
                                        .accessibilityHint(loc: "rel.unfollow.hint")
                                    }
                                }
                        }
                        .onDelete { indexSet in
                            if let idx = indexSet.first, idx < filteredActors.count {
                                let actor = filteredActors[idx]
                                actorToBlock = actor
                                if confirmBlocks {
                                    isShowingBlockConfirm = true
                                } else {
                                    performBlock(actor)
                                }
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)
                .environment(\.showActorDescriptions, showActorDescriptions)
                .overlay(alignment: .bottom) {
                    if actionsVM?.isBlockingBack ?? false, (actionsVM?.blockBackTotal ?? 0) > 0 {
                        VStack(spacing: 6) {
                            ProgressView(value: Double(actionsVM?.blockBackCompleted ?? 0), total: Double(actionsVM?.blockBackTotal ?? 0))
                                .progressViewStyle(.linear)
                                .tint((actionsVM?.blockBackFailureCount ?? 0) > 0 ? Color.orange : Color.skyPrimary)
                            HStack {
                                Text(
                                    loc("profile.block_back.progress")
                                        .replacingOccurrences(of: "{completed}", with: "\(actionsVM?.blockBackCompleted ?? 0)")
                                        .replacingOccurrences(of: "{total}", with: "\(actionsVM?.blockBackTotal ?? 0)")
                                )
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                Spacer()
                            }
                            HStack(spacing: 12) {
                                Label("\(actionsVM?.blockBackSuccessCount ?? 0)", systemImage: "checkmark.circle.fill")
                                    .font(.caption)
                                    .foregroundStyle(Color.successGreen)
                                if (actionsVM?.blockBackFailureCount ?? 0) > 0 {
                                    Label("\(actionsVM?.blockBackFailureCount ?? 0)", systemImage: "xmark.circle.fill")
                                        .font(.caption)
                                        .foregroundStyle(Color.errorRed)
                                }
                                Spacer()
                            }
                            if let handle = actionsVM?.blockBackCurrentHandle {
                                HStack(spacing: 4) {
                                    ProgressView()
                                        .scaleEffect(0.5)
                                    Text(
                                        loc("profile.block_back.progress.current")
                                            .replacingOccurrences(of: "{handle}", with: handle)
                                    )
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    Spacer()
                                }
                                .transition(.opacity)
                            }
                        }
                        .padding(12)
                        .background(.regularMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .padding()
                        .animation(.default.speed(1.5), value: actionsVM?.blockBackCurrentHandle)
                    } else if actionsVM?.isBlockingBack ?? false {
                        HStack(spacing: 8) {
                            ProgressView()
                                .scaleEffect(0.7)
                            Text(loc("profile.block_back.preparing"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(12)
                        .background(.regularMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .padding()
                    } else if actionsVM?.showBlockBackResult ?? false {
                        HStack(spacing: 8) {
                            if (actionsVM?.blockBackFailureCount ?? 0) == 0 {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(Color.successGreen)
                            } else {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(Color.warningOrange)
                            }
                            Text(blockBackResultSummary)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(12)
                        .background(.regularMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .padding()
                        .transition(.opacity)
                    }
                }
            }
        }
        .pageTitle(
            isRefreshing
                ? modeLocalized
                : "\(modeLocalized) (\(clearskyTotal ?? actors.count))"
        )
        .toolbarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                HStack(spacing: 6) {
                    Text(modeLocalized)
                        .font(.headline)
                    if isRefreshing {
                        ProgressView()
                            .scaleEffect(0.8)
                    } else {
                        Text(verbatim: "(\(clearskyTotal ?? actors.count))")
                            .foregroundStyle(.secondary)
                            .font(.subheadline)
                    }
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 16) {
                    if isSelectMode {
                        Button(loc("actions.cancel"), role: .cancel) {
                            isSelectMode = false
                            selectedDIDs.removeAll()
                        }
                        Button {
                            showBulkBlockConfirm = true
                        } label: {
                            Label(loc("rel.block_selected").replacingOccurrences(of: "{count}", with: "\(selectedDIDs.count)"), systemImage: "hand.raised.fill")
                        }
                        .disabled(selectedDIDs.isEmpty)
                        .buttonStyle(.borderedProminent)
                    } else {
                        Button {
                            isSelectMode = true
                        } label: {
                            Text(loc("actions.select"))
                        }
                        if !actors.isEmpty, mode == .blockedBy {
                            bulkAddToListsMenu
                        }
                        Menu {
                            Toggle(isOn: $showActorDescriptions) {
                                Label {
                                    Text(loc("rel.show_descriptions"))
                                } icon: {
                                    Image(systemName: "text.alignleft")
                                }
                            }

                            if mode == .following {
                                Toggle(isOn: $showActorStats) {
                                    Label {
                                        Text(loc("rel.show_stats"))
                                    } icon: {
                                        Image(systemName: "chart.bar")
                                    }
                                }
                            }

                            Divider()

                            if mode == .following {
                                Button {
                                    isShowingJSONImportPicker = true
                                } label: {
                                    Label { Text(loc("rel.import_json")) } icon: { Image(systemName: "square.and.arrow.down") }
                                }

                                Button(role: .destructive) {
                                    let count = actors.filter { actor in
                                        guard let stats = profileStats[actor.did] else { return false }
                                        return stats.posts == 0
                                    }.count
                                    blockNoPostsCount = count
                                    showBlockNoPostsConfirm = true
                                } label: {
                                    Label { Text(loc("rel.block_no_posts")) } icon: { Image(systemName: "hand.raised.slash") }
                                }
                                .disabled(isLoadingStats || profileStats.isEmpty)
                            }

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
                } // end else (select mode)
            }
        }
        .refreshable {
            await refresh()
        }
        .navigationDestination(item: $selectedActor) { actor in
            BlueskyProfileView(
                member: BlueskyListMember(recordURI: "rel:\(actor.did)", actor: actor),
                list: nil
            )
        }
        .fileImporter(
            isPresented: $isShowingJSONImportPicker,
            allowedContentTypes: [.json]
        ) { result in
            handleJSONImport(result)
        }
        .confirmationDialog(
            loc("rel.add_all_to_list"),
            isPresented: $isChoosingJSONImportList,
            titleVisibility: .visible
        ) {
            ForEach(availableTargetLists) { list in
                Button {
                    importJSONTargets(to: list)
                } label: {
                    Label(list.name, systemImage: list.kind.symbolName)
                }
            }
            Button(loc("actions.cancel"), role: .cancel) {}
        } message: {
            Text("\(importedJSONTargets.count)")
        }
        .alert(loc("rel.import_json.import_error"), isPresented: .constant(jsonImportError != nil)) {
            Button(loc("actions.ok")) { jsonImportError = nil }
        } message: {
            Text(jsonImportError ?? "")
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
                        try await container.social.blockActor(
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
        .confirmationDialog(
            loc("rel.block_no_posts.confirm")
                .replacingOccurrences(of: "{count}", with: "\(blockNoPostsCount)"),
            isPresented: $showBlockNoPostsConfirm,
            titleVisibility: .visible
        ) {
            Button(loc("rel.block"), role: .destructive) {
                showBlockNoPostsConfirm = false
                guard let account = accountStore.activeAccount,
                      let appPassword = accountStore.appPassword(for: account) else { return }
                let targets = actors.compactMap { actor -> PendingLikerTarget? in
                    guard let stats = profileStats[actor.did], stats.posts == 0 else { return nil }
                    return PendingLikerTarget(did: actor.did, handle: actor.handle)
                }
                guard !targets.isEmpty else { return }
                batchOperationConfig = BatchOperationConfig(
                    targets: targets,
                    mode: .block(account: account, appPassword: appPassword)
                )
            }
            Button(loc("actions.cancel"), role: .cancel) {
                showBlockNoPostsConfirm = false
            }
        } message: {
            Text(loc("rel.block_no_posts.confirm.message"))
        }
        .confirmationDialog(
            loc("rel.block_selected").replacingOccurrences(of: "{count}", with: "\(selectedActors.count)"),
            isPresented: $showBulkBlockConfirm,
            titleVisibility: .visible
        ) {
            Button(loc("rel.block").replacingOccurrences(of: "{count}", with: "\(selectedActors.count)"), role: .destructive) {
                guard let account = accountStore.activeAccount,
                      let appPassword = accountStore.appPassword(for: account) else { return }
                let targets = selectedActors.map { PendingLikerTarget(did: $0.did, handle: $0.handle) }
                guard !targets.isEmpty else { return }
                batchOperationConfig = BatchOperationConfig(
                    targets: targets,
                    mode: .block(account: account, appPassword: appPassword)
                )
                isSelectMode = false
                selectedDIDs.removeAll()
            }
            Button(loc("actions.cancel"), role: .cancel) {
                showBulkBlockConfirm = false
            }
        } message: {
            Text(loc("rel.block_selected.message"))
        }
        .alert(Text(loc: "profile.block_back.confirm.first.title"), isPresented: $showBlockBackConfirm1) {
            Button(loc("actions.cancel"), role: .cancel) {}
            Button(loc("profile.block_back.action")) {
                showBlockBackConfirm2 = true
            }
        } message: {
            if let count = actionsVM?.unblockedBlockersCount {
                Text(loc("profile.block_back.confirm.first.message").replacingOccurrences(of: "{count}", with: "\(count)"))
            }
        }
        .alert(Text(loc: "profile.block_back.confirm.second.title"), isPresented: $showBlockBackConfirm2) {
            Button(loc("actions.cancel"), role: .cancel) {}
            Button(loc("profile.block_back.action"), role: .destructive) {
                if let account = accountStore.activeAccount,
                   let appPassword = accountStore.appPassword(for: account)
                {
                    Task {
                        await blockBack(account: account, appPassword: appPassword)
                    }
                }
            }
        } message: {
            if let count = actionsVM?.unblockedBlockersCount {
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
                ListPickerSheet(actor: actor, account: account, appPassword: appPassword, client: container.blueskyClient)
                    .environmentObject(accountStore)
                    .environmentObject(container.blueskyClient)
            }
        }
        .sheet(isPresented: .init(get: { shareFileURL != nil }, set: {
            if !$0 {
                shareFileURL = nil
            }
        })) {
            if let url = shareFileURL {
                ShareSheet(activityItems: [url])
            }
        }
        .sheet(item: $batchOperationConfig) { config in
            BatchOperationProgressView(config: config)
                .environmentObject(container.blueskyClient)
                .environmentObject(localizationManager)
        }
        .task {
            await loadAvailableTargetLists()
        }
        .task {
            wireActionsVM()
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
            .disabled(actionsVM?.isBlockingBack ?? false)
            if availableTargetLists.isEmpty {
                if listsLoaded {
                    Button {} label: {
                        Label(loc("rel.no_lists_available"), systemImage: "tray")
                    }
                    .disabled(true)
                } else {
                    Button {
                        Task { await loadAvailableTargetLists() }
                    } label: {
                        Label(loc("rel.loading_lists"), systemImage: "arrow.triangle.2.circlepath")
                    }
                    .disabled(true)
                }
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

    /// Reads a relationship JSON export and prepares its actors for add-to-list import.
    private func handleJSONImport(_ result: Result<URL, Error>) {
        switch result {
        case let .success(url):
            do {
                guard url.startAccessingSecurityScopedResource() else {
                    jsonImportError = loc("account.import.access_error")
                    return
                }
                defer { url.stopAccessingSecurityScopedResource() }

                let data = try Data(contentsOf: url)
                let object = try JSONSerialization.jsonObject(with: data)
                guard let rows = object as? [[String: Any]] else {
                    jsonImportError = loc("account.import.invalid_format")
                    return
                }

                var seenDIDs: Set<String> = []
                let targets = rows.compactMap { row -> PendingLikerTarget? in
                    guard let did = (row["did"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
                          !did.isEmpty,
                          seenDIDs.insert(did).inserted
                    else {
                        return nil
                    }
                    let handle = (row["handle"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
                    return PendingLikerTarget(did: did, handle: handle?.isEmpty == false ? handle : nil)
                }

                guard !targets.isEmpty else {
                    jsonImportError = loc("rel.import_json.empty")
                    return
                }

                importedJSONTargets = targets
                if availableTargetLists.isEmpty {
                    Task {
                        await loadAvailableTargetLists()
                        if availableTargetLists.isEmpty {
                            jsonImportError = loc("rel.no_lists_desc")
                        } else {
                            isChoosingJSONImportList = true
                        }
                    }
                } else {
                    isChoosingJSONImportList = true
                }
            } catch {
                jsonImportError = error.localizedDescription
            }
        case let .failure(error):
            jsonImportError = error.localizedDescription
        }
    }

    /// Adds JSON-imported relationship targets to the selected destination list.
    private func importJSONTargets(to list: BlueskyList) {
        let targets = importedJSONTargets
        guard !targets.isEmpty else { return }

        if list.kind == .internal {
            for target in targets {
                internalListStore.addMember(
                    did: target.did,
                    handle: target.handle ?? target.did,
                    to: internalListStore.listID(from: list.id)
                )
            }
            importedJSONTargets = []
        } else {
            guard let account = accountStore.activeAccount,
                  let appPassword = accountStore.appPassword(for: account) else { return }
            batchOperationConfig = BatchOperationConfig(
                targets: targets,
                mode: .addToList(list: list, account: account, appPassword: appPassword)
            )
            importedJSONTargets = []
        }
    }

    /// Fetches the count of unblocked blockers and presents the first confirmation dialog.
    private func handleBlockAllBack() async {
        guard accountStore.activeAccount != nil else { return }
        await actionsVM?.fetchBlockCounts(isOwnProfile: true)
        guard let count = actionsVM?.unblockedBlockersCount, count > 0 else {
            showBlockBackAllClear = true
            return
        }
        showBlockBackConfirm1 = true
    }

    /// Delegates to the shared VM.
    private func blockBack(account _: AppAccount, appPassword _: String) async {
        await actionsVM?.blockBack(actors: nil)
    }

    /// Blocks the given actor immediately without confirmation dialog.
    private func performBlock(_ actor: BlueskyActor) {
        guard let account = accountStore.activeAccount,
              let appPassword = accountStore.appPassword(for: account) else { return }
        Task {
            do {
                try await container.social.blockActor(
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

    /// Force-unfollows the given follower (block + immediate unblock).
    private func performForceUnfollow(_ actor: BlueskyActor) {
        guard let account = accountStore.activeAccount,
              let appPassword = accountStore.appPassword(for: account) else { return }
        statusMessage = loc("rel.force_unfollow.progress")
        Task {
            do {
                try await container.social.softBlockActor(
                    did: actor.did,
                    account: account,
                    appPassword: appPassword
                )
                actors.removeAll { $0.did == actor.did }
                statusMessage = loc("rel.force_unfollow.done")
            } catch {
                errorMessage = AppError.userMessage(from: error)
                statusMessage = nil
            }
        }
    }

    /// Unblocks the given actor in Blocking mode using the cached block record URI.
    private func performUnblock(_ actor: BlueskyActor) {
        guard let account = accountStore.activeAccount,
              let appPassword = accountStore.appPassword(for: account),
              let recordURI = blockRecordURIs[actor.did]
        else {
            errorMessage = loc("rel.unblock.no_uri")
            return
        }
        Task {
            do {
                try await container.social.unblockActor(
                    recordURI: recordURI,
                    account: account,
                    appPassword: appPassword
                )
                actors.removeAll { $0.did == actor.did }
                blockRecordURIs.removeValue(forKey: actor.did)
            } catch {
                errorMessage = AppError.userMessage(from: error)
            }
        }
    }

    /// A localized summary of the block-back operation result.
    private var blockBackResultSummary: String {
        if (actionsVM?.blockBackFailureCount ?? 0) == 0 {
            loc("profile.block_back.result_success")
                .replacingOccurrences(of: "{count}", with: "\(actionsVM?.blockBackSuccessCount ?? 0)")
        } else {
            loc("profile.block_back.result")
                .replacingOccurrences(of: "{success}", with: "\(actionsVM?.blockBackSuccessCount ?? 0)")
                .replacingOccurrences(of: "{fail}", with: "\(actionsVM?.blockBackFailureCount ?? 0)")
        }
    }

    /// Loads the user's moderation, internal, and regular lists for the bulk add-all menu.
    private func loadAvailableTargetLists() async {
        var lists: [BlueskyList] = []
        if let account = accountStore.activeAccount,
           let appPassword = accountStore.appPassword(for: account)
        {
            do {
                lists = try await container.list.fetchLists(for: account, appPassword: appPassword)
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
        listsLoaded = true
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

    /// Row label for the actor list, extracted for type-check performance.
    private func actorRowLabel(actor: BlueskyActor, index: Int) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 0) {
                BlueskyActorRow(actor: actor) {
                    if actor.isNew {
                        Text(loc("rel.new_badge"))
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(Color.warningOrange)
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
                        .foregroundStyle(.secondary)
                }
            }

            // Follow-relationship badges below the handle
            MemberFollowBadgesView(viewerState: effectiveViewerState(for: actor))
                .padding(.leading, 46) // indent below text column (avatar 36 + spacing 10)

            if mode == .following, showActorStats, let stats = profileStats[actor.did] {
                HStack(spacing: 4) {
                    Image(systemName: "text.bubble")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    Text("\(stats.posts)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text("·")
                        .foregroundStyle(.tertiary)
                    Image(systemName: "person.fill")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    Text("\(stats.followers)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text("·")
                        .foregroundStyle(.tertiary)
                    Image(systemName: "person.2.fill")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    Text("\(stats.following)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.leading, 46) // align with text below avatar
                .padding(.bottom, 4)
            }
        }
    }

    // MARK: - Follow / Unfollow via Double-Tap

    /// Returns the effective viewer state for an actor, merging API data
    /// with any pending optimistic follow/unfollow action.
    private func effectiveViewerState(for actor: BlueskyActor) -> BlueskyViewerState? {
        guard var state = actor.viewerState else { return nil }
        if pendingFollowActions.contains(actor.did) {
            state = state.withOptimisticFollow(following: true, recordURI: optimisticFollowRecordURIs[actor.did])
        }
        if pendingUnfollowActions.contains(actor.did) {
            state = state.withOptimisticFollow(following: false)
        }
        return state
    }

    /// Toggles follow state for an actor with optimistic UI feedback.
    /// Double-tap a row to follow (if not following) or unfollow (if following).
    private func toggleFollow(actor: BlueskyActor) async {
        guard let activeAccount = accountStore.activeAccount,
              let appPassword = accountStore.appPassword(for: activeAccount)
        else { return }

        let did = actor.did
        let isCurrentlyFollowing = pendingFollowActions.contains(did)
            || (actor.viewerState?.isFollowing == true && !pendingUnfollowActions.contains(did))

        if isCurrentlyFollowing {
            // Optimistic: show unfollowed
            pendingUnfollowActions.insert(did)
            pendingFollowActions.remove(did)

            guard let recordURI = optimisticFollowRecordURIs[did] ?? actor.viewerState?.followingRecordURI else {
                pendingUnfollowActions.remove(did)
                return
            }

            do {
                try await container.social.unfollowActor(
                    recordURI: recordURI,
                    account: activeAccount,
                    appPassword: appPassword
                )
                optimisticFollowRecordURIs.removeValue(forKey: did)
                // Optimistic: pendingUnfollowActions keeps the badge hidden
                // On the next full reload, viewerState will reflect the change.
            } catch {
                // Revert optimistic update
                pendingUnfollowActions.remove(did)
            }
        } else {
            // Optimistic: show following
            pendingFollowActions.insert(did)
            pendingUnfollowActions.remove(did)

            do {
                let recordURI = try await container.social.followActor(
                    did: did,
                    account: activeAccount,
                    appPassword: appPassword
                )
                optimisticFollowRecordURIs[did] = recordURI
                // Optimistic: pendingFollowActions keeps the badge visible
            } catch {
                // Revert optimistic update
                pendingFollowActions.remove(did)
            }
        }
    }

    private var cacheKey: String? {
        guard let accountDID = accountStore.activeAccount?.did else { return nil }
        let subject = profileDID ?? accountDID
        return "\(mode.rawValue)_\(subject)"
    }

    /// Fetches profile stats (posts, followers, following) for the given actors
    /// using the batch public API. Stores results in `profileStats`.
    private func fetchStats(for actors: [BlueskyActor]) async {
        let dids = actors.map(\.did)
        guard !dids.isEmpty else { return }
        isLoadingStats = true
        let stats = await (try? LiveBlueskyClient.fetchProfileStats(dids: dids) { _, _ in }) ?? [:]
        await MainActor.run {
            profileStats = stats
            isLoadingStats = false
        }
    }

    /// Loads cached data first, then fetches fresh data from the API.
    private func load() async {
        guard let account = accountStore.activeAccount
        else {
            errorMessage = String.localized("rel.select_account_first")
            isLoading = false
            return
        }
        let appPassword = accountStore.appPassword(for: account)

        actors = []
        profileStats = [:]
        clearskyTotal = nil
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
        guard let account = accountStore.activeAccount else { return }
        let appPassword = accountStore.appPassword(for: account)
        // Clear count so title shows loading state
        clearskyTotal = nil
        isRefreshing = true
        await fetchFromAPI(account: account, appPassword: appPassword)
        isRefreshing = false
    }

    /// Fetches actors from the Bluesky/CloudSky API based on mode, then caches the result.
    private func fetchFromAPI(account: AppAccount, appPassword: String?) async {
        do {
            let did = profileDID ?? account.did ?? account.handle
            let result: [BlueskyActor]
            switch mode {
            case .followers:
                result = try await container.profile.fetchFollowers(actor: did, account: account, appPassword: appPassword)
                clearskyTotal = initialCount ?? result.count
                onCountUpdate?(mode, result.count)
            case .following:
                result = try await container.profile.fetchFollowing(actor: did, account: account, appPassword: appPassword)
                clearskyTotal = initialCount ?? result.count
                onCountUpdate?(mode, result.count)
            case .blocking:
                let r = try await container.clearsky.fetchBlockedActors(
                    account: account,
                    appPassword: appPassword,
                    onProgress: updateClearskyCount
                )
                result = r.actors
                clearskyTotal = r.totalCount
                onCountUpdate?(mode, r.totalCount)
            case .blockedBy:
                let r = try await container.clearsky.fetchBlockedByActors(
                    account: account,
                    appPassword: appPassword,
                    onProgress: updateClearskyCount
                )
                result = r.actors
                clearskyTotal = r.totalCount
                onCountUpdate?(mode, r.totalCount)
            }
            if mode == .blocking || mode == .blockedBy {
                actors = result.sorted { ($0.blockedDate ?? .distantPast) > ($1.blockedDate ?? .distantPast) }
            } else {
                actors = result
            }

            // Fetch block record URIs for unblocking in Blocking mode
            if mode == .blocking {
                if let uris = try? await container.social.fetchExistingBlockRecordURIs(account: account, appPassword: appPassword) {
                    blockRecordURIs = uris
                }
            }

            // Show status if loaded count differs from expected total
            if let expected = clearskyTotal, expected != actors.count, mode != .blocking, mode != .blockedBy {
                statusMessage = String.localized("rel.loaded_status", replacements: ["count": "\(actors.count)", "total": "\(expected)"])
            }

            isLoading = false

            // Fetch profile stats for following mode
            if mode == .following, !actors.isEmpty {
                await fetchStats(for: actors)
            }
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

    @MainActor
    private func updateClearskyCount(_ count: Int) async {
        clearskyTotal = count
        onCountUpdate?(mode, count)
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
