import SwiftUI

private struct PendingLikerTarget: Identifiable {
    let did: String
    let handle: String?

    var id: String {
        did
    }
}

struct MentionsSearchView: View {
    let did: String
    let handle: String
    let displayName: String

    @StateObject private var viewModel: MentionsSearchViewModel
    @EnvironmentObject var accountStore: AccountStore
    @EnvironmentObject var blueskyClient: LiveBlueskyClient
    @Environment(\.dismiss) private var dismiss
    @State private var selectedPostURI: String?
    @State private var imagePreview: ImagePreviewCollection?
    @State private var videoPreviewURL: URL?
    @State private var showLikesForURI: String?
    @State private var loadMoreTask: Task<Void, Never>?
    @State private var showProfileFor: BlueskyActor?
    @State private var searchAccount: AppAccount?
    @State private var hasAppeared = false
    @State private var availableTargetLists: [BlueskyList] = []
    @State private var isFetchingLikers = false
    @State private var pendingLikerTargets: [PendingLikerTarget] = []
    @State private var showBlockLikersConfirmation = false
    @State private var isCheckingLikers = false
    @State private var isBlockingLikers = false
    @State private var isAddingLikersToList = false
    @State private var blockedCount = 0
    @State private var alreadyBlockedCount = 0
    @State private var totalToBlock = 0
    @State private var currentBlockingHandle: String?
    @State private var addedCount = 0
    @State private var totalToAdd = 0
    @State private var currentAddingHandle: String?
    @State private var blockError: String?
    @State private var blockSuccessCount: Int?
    @State private var addSuccessMessage: String?

    init(did: String, handle: String, displayName: String) {
        self.did = did
        self.handle = handle
        self.displayName = displayName
        _viewModel = StateObject(wrappedValue: MentionsSearchViewModel(did: did, handle: handle))
    }

    @EnvironmentObject private var localizationManager: LocalizationManager
    var body: some View {
        List {
            searchAccountSection

            if isCheckingLikers {
                checkingProgressSection
            }

            if isBlockingLikers {
                blockingProgressSection
            }

            if isAddingLikersToList {
                addingProgressSection
            }

            if isFetchingLikers {
                HStack {
                    Spacer()
                    ProgressView("post.block_likers.fetching")
                    Spacer()
                }
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
            }

            if viewModel.isLoading, viewModel.entries.isEmpty {
                HStack {
                    Spacer()
                    LoadingPanel(message: loc("mentions.loading"))
                    Spacer()
                }
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
            } else if let error = viewModel.errorMessage, viewModel.entries.isEmpty {
                HStack {
                    Spacer()
                    ContentUnavailableView(
                        loc("list.detail.alert_title"),
                        systemImage: "exclamationmark.bubble",
                        description: Text(error)
                    )
                    Spacer()
                }
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
            } else if viewModel.entries.isEmpty, !isFetchingLikers {
                HStack {
                    Spacer()
                    ContentUnavailableView(
                        loc("mentions.empty"),
                        systemImage: "at",
                        description: Text(loc: "mentions.empty_desc")
                    )
                    Spacer()
                }
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
            } else {
                ForEach(viewModel.entries, id: \.post.uri) { entry in
                    PostRowView(
                        entry: entry,
                        onTapImage: { index in
                            let allImages = entry.post.embed?.images ?? []
                            let urls = allImages.compactMap { $0.fullsize.flatMap(URL.init) }
                            guard index < urls.count else { return }
                            imagePreview = ImagePreviewCollection(urls: urls, initialIndex: index)
                        },
                        onPlayVideo: {
                            if let playlist = entry.post.embed?.video?.playlist, let url = URL(string: playlist) {
                                videoPreviewURL = url
                            }
                        },
                        onShowLikes: { showLikesForURI = entry.post.uri },
                        onOpenProfile: { _ in
                            let author = entry.post.safeAuthor
                            showProfileFor = BlueskyActor(
                                did: author.did ?? "",
                                handle: author.handle ?? "",
                                displayName: author.displayName,
                                avatarURL: author.avatar.flatMap(URL.init)
                            )
                        },
                        onBlockAllLikers: { handleBlockAllLikers(postURI: entry.post.uri) },
                        availableLikerTargetLists: availableTargetLists,
                        onAddAllLikersToList: { list in
                            handleAddAllLikersToList(postURI: entry.post.uri, list: list)
                        }
                    )
                    .buttonStyle(.plain)
                    .onAppear {
                        if entry.post.uri == viewModel.entries.last?.post.uri {
                            Task { await loadMore() }
                        }
                    }
                }
                if viewModel.isLoadingMore {
                    HStack {
                        Spacer()
                        ProgressView()
                            .scaleEffect(0.8)
                        Spacer()
                    }
                    .listRowSeparator(.hidden)
                }
                if !viewModel.hasMore, !viewModel.entries.isEmpty {
                    Text(loc: "mentions.end")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity)
                        .listRowSeparator(.hidden)
                }
            }
        }
        .listStyle(.insetGrouped)
        .refreshable {
            await refresh()
        }
        .navigationTitle(Text(loc: "mentions.title"))
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $selectedPostURI) { uri in
            ThreadView(postURI: uri)
                .environmentObject(accountStore)
                .environmentObject(blueskyClient)
        }
        .fullScreenCover(item: $imagePreview) { preview in
            ImageCarouselView(urls: preview.urls, initialIndex: preview.initialIndex) {
                imagePreview = nil
            }
        }
        .fullScreenCover(item: $videoPreviewURL) { url in
            VideoPlayerView(url: url) {
                videoPreviewURL = nil
            }
        }
        .sheet(item: $showLikesForURI) { uri in
            LikesListView(uri: uri)
                .environmentObject(accountStore)
                .environmentObject(blueskyClient)
        }
        .navigationDestination(item: $showProfileFor) { actor in
            BlueskyProfileView(
                member: BlueskyListMember(recordURI: "mention:\(actor.did)", actor: actor),
                list: nil
            )
            .environmentObject(accountStore)
            .environmentObject(blueskyClient)
        }
        .alert(String.localized("post.block_likers.confirm_title", replacements: ["count": "\(pendingLikerTargets.count)"]), isPresented: $showBlockLikersConfirmation) {
            Button(loc("post.block_likers.confirm_block"), role: .destructive) {
                let targets = pendingLikerTargets
                showBlockLikersConfirmation = false
                Task { await blockLikers(targets) }
            }
            Button(loc("actions.cancel"), role: .cancel) {
                resetPendingLikerTargets()
            }
        } message: {
            let handles = pendingLikerTargets.prefix(5).map { target in
                if let handle = target.handle, !handle.isEmpty {
                    return "@\(handle)"
                }
                return target.did
            }.joined(separator: "\n")
            let remainder = pendingLikerTargets.count > 5 ? "\n…and \(pendingLikerTargets.count - 5) more" : ""
            Text(verbatim: loc("post.block_likers.confirm_message").replacingOccurrences(of: "{count}", with: "\(pendingLikerTargets.count)") + "\n\n" + handles + remainder)
        }
        .alert("post.block_likers.done_title", isPresented: .init(get: { blockSuccessCount != nil }, set: { if !$0 { blockSuccessCount = nil } })) {
            Button("actions.ok") { blockSuccessCount = nil }
        } message: {
            if let count = blockSuccessCount {
                Text(verbatim: loc("post.block_likers.done").replacingOccurrences(of: "{count}", with: "\(count)"))
            }
        }
        .alert("post.add_likers.done_title", isPresented: .init(get: { addSuccessMessage != nil }, set: { if !$0 { addSuccessMessage = nil } })) {
            Button("actions.ok") { addSuccessMessage = nil }
        } message: {
            if let addSuccessMessage {
                Text(verbatim: addSuccessMessage)
            }
        }
        .alert("list.detail.alert_title", isPresented: .init(get: { blockError != nil }, set: { if !$0 { blockError = nil } })) {
            Button("actions.ok") { blockError = nil }
        } message: {
            if let error = blockError {
                Text(error)
            }
        }
        .task {
            if !hasAppeared {
                hasAppeared = true
                if let prefID = accountStore.preferredSearchAccountID,
                   let prefAccount = accountStore.accounts.first(where: { $0.id == prefID })
                {
                    searchAccount = prefAccount
                } else {
                    searchAccount = accountStore.activeAccount
                }
                await loadInitial()
                await loadAvailableTargetLists()
            }
        }
        .onChange(of: accountStore.activeAccount?.id) { _, _ in
            Task {
                await loadAvailableTargetLists()
            }
        }
        .onDisappear {
            loadMoreTask?.cancel()
        }
    }

    private var searchAccountSection: some View {
        Group {
            if let searchAccount {
                searchAccountRow(searchAccount)
            }
        }
        .listRowInsets(EdgeInsets(top: -4, leading: 0, bottom: 0, trailing: 0))
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }

    private func searchAccountRow(_ account: AppAccount) -> some View {
        HStack(spacing: 14) {
            if let avatarURL = account.avatarURL {
                ThumbnailImageView(url: avatarURL, maxPixelSize: 64) {
                    avatarPlaceholder(for: account)
                }
                .scaledToFill()
                .frame(width: 32, height: 32)
                .clipShape(Circle())
            } else {
                avatarPlaceholder(for: account)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(loc: "mentions.searching_as")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.primary)
                Text(account.displayName)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 16)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.skyPrimary.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.skyPrimary.opacity(0.12), lineWidth: 1)
        )
    }

    private func avatarPlaceholder(for account: AppAccount) -> some View {
        Circle()
            .fill(Color.skyPrimary.opacity(0.25))
            .frame(width: 32, height: 32)
            .overlay {
                Text(account.displayName.prefix(1).uppercased())
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
            }
    }

    private var checkingProgressSection: some View {
        VStack(spacing: 12) {
            HStack {
                Text(loc: "post.block_likers.checking_title")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                ProgressView()
                    .scaleEffect(0.8)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.skyPrimary.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.skyPrimary.opacity(0.12), lineWidth: 1)
        )
        .listRowSeparator(.hidden)
    }

    private var blockingProgressSection: some View {
        VStack(spacing: 12) {
            HStack {
                Text(loc: "post.block_likers.blocking_title")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text("\(blockedCount)/\(totalToBlock)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            ProgressView(value: Double(blockedCount), total: Double(max(totalToBlock, 1)))
                .progressViewStyle(.linear)
            HStack(spacing: 16) {
                Label(
                    loc("post.block_likers.blocked_now").replacingOccurrences(of: "{count}", with: "\(blockedCount)"),
                    systemImage: "hand.raised.fill"
                )
                .font(.caption2)
                .foregroundStyle(.secondary)
                Label(
                    loc("post.block_likers.already_blocked").replacingOccurrences(of: "{count}", with: "\(alreadyBlockedCount)"),
                    systemImage: "checkmark.circle.fill"
                )
                .font(.caption2)
                .foregroundStyle(.secondary)
                Spacer()
            }
            if let handle = currentBlockingHandle {
                Text(verbatim: handle)
                    .font(.caption.monospaced())
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.skyPrimary.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.skyPrimary.opacity(0.12), lineWidth: 1)
        )
        .listRowSeparator(.hidden)
    }

    private var addingProgressSection: some View {
        VStack(spacing: 12) {
            HStack {
                Text(loc: "post.add_likers.adding_title")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text("\(addedCount)/\(totalToAdd)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            ProgressView(value: Double(addedCount), total: Double(max(totalToAdd, 1)))
                .progressViewStyle(.linear)
            if let handle = currentAddingHandle {
                Text(verbatim: handle)
                    .font(.caption.monospaced())
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.skyPrimary.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.skyPrimary.opacity(0.12), lineWidth: 1)
        )
        .listRowSeparator(.hidden)
    }

    private func handleBlockAllLikers(postURI: String) {
        Task {
            guard let targets = await fetchLikerTargets(for: postURI) else { return }
            pendingLikerTargets = targets
            showBlockLikersConfirmation = true
        }
    }

    private func handleAddAllLikersToList(postURI: String, list: BlueskyList) {
        Task {
            guard let targets = await fetchLikerTargets(for: postURI) else { return }
            guard let account = accountStore.activeAccount,
                  let appPassword = accountStore.appPassword(for: account) else { return }
            await addLikers(targets, to: list, account: account, appPassword: appPassword)
        }
    }

    private func fetchLikerTargets(for postURI: String) async -> [PendingLikerTarget]? {
        guard let account = searchAccount,
              let appPassword = accountStore.appPassword(for: account) else { return nil }
        isFetchingLikers = true
        resetPendingLikerTargets()
        do {
            var allLikes: [LikeItem] = []
            var cursor: String?
            repeat {
                let response = try await blueskyClient.fetchLikes(uri: postURI, cursor: cursor, account: account, appPassword: appPassword)
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

    private func blockLikers(_ targets: [PendingLikerTarget]) async {
        guard let account = accountStore.activeAccount,
              let appPassword = accountStore.appPassword(for: account) else { return }
        guard !targets.isEmpty else { return }

        isCheckingLikers = true
        let blockedDIDs: Set<String>
        do {
            let blockedResult = try await blueskyClient.fetchBlockedActors(account: account, appPassword: appPassword)
            blockedDIDs = Set(blockedResult.actors.map(\.did))
        } catch {
            blockedDIDs = []
            AppLogger.moderation.error("Failed to fetch blocked actors: \(error.localizedDescription, privacy: .public)")
        }
        isCheckingLikers = false
        let filteredTargets = targets.filter { !blockedDIDs.contains($0.did) }
        guard !filteredTargets.isEmpty else {
            blockSuccessCount = 0
            return
        }

        isBlockingLikers = true
        blockedCount = 0
        alreadyBlockedCount = targets.count - filteredTargets.count
        totalToBlock = filteredTargets.count
        currentBlockingHandle = nil
        var lastError: String?
        for target in filteredTargets {
            currentBlockingHandle = displayHandle(for: target)
            do {
                try await blueskyClient.blockActor(did: target.did, account: account, appPassword: appPassword)
                blockedCount += 1
                await Task.yield()
            } catch {
                lastError = AppError.userMessage(from: error)
                AppLogger.moderation.error("Failed to block \(target.did): \(error.localizedDescription, privacy: .public)")
            }
        }
        currentBlockingHandle = nil
        isBlockingLikers = false
        resetPendingLikerTargets()
        if blockedCount > 0 {
            blockSuccessCount = blockedCount
        }
        if let lastError {
            blockError = lastError
        }
    }

    private func addLikers(_ targets: [PendingLikerTarget], to list: BlueskyList, account: AppAccount, appPassword: String) async {
        guard !targets.isEmpty else { return }

        isCheckingLikers = true
        let memberDIDs: Set<String>
        do {
            let members = try await blueskyClient.fetchListMembers(list: list, account: account, appPassword: appPassword)
            memberDIDs = Set(members.map(\.actor.did))
        } catch {
            memberDIDs = []
            AppLogger.moderation.error("Failed to fetch list members: \(error.localizedDescription, privacy: .public)")
        }
        isCheckingLikers = false
        let filteredTargets = targets.filter { !memberDIDs.contains($0.did) }
        guard !filteredTargets.isEmpty else {
            addSuccessMessage = loc("post.add_likers.done")
                .replacingOccurrences(of: "{count}", with: "0")
                .replacingOccurrences(of: "{list}", with: list.name)
            return
        }

        isAddingLikersToList = true
        addedCount = 0
        totalToAdd = filteredTargets.count
        currentAddingHandle = nil
        var lastError: String?
        for target in filteredTargets {
            currentAddingHandle = displayHandle(for: target)
            do {
                _ = try await blueskyClient.addActor(did: target.did, to: list, account: account, appPassword: appPassword)
                addedCount += 1
                await Task.yield()
            } catch {
                lastError = AppError.userMessage(from: error)
                AppLogger.moderation.error("Failed to add \(target.did) to \(list.name, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }
        currentAddingHandle = nil
        isAddingLikersToList = false
        if addedCount > 0 {
            addSuccessMessage = loc("post.add_likers.done")
                .replacingOccurrences(of: "{count}", with: "\(addedCount)")
                .replacingOccurrences(of: "{list}", with: list.name)
        }
        if let lastError {
            blockError = lastError
        }
    }

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

    private func displayHandle(for target: PendingLikerTarget) -> String {
        if let handle = target.handle, !handle.isEmpty {
            return "@\(handle)"
        }
        return target.did
    }

    private func resetPendingLikerTargets() {
        pendingLikerTargets = []
        showBlockLikersConfirmation = false
    }

    private func loadAvailableTargetLists() async {
        guard let account = accountStore.activeAccount,
              let appPassword = accountStore.appPassword(for: account)
        else {
            availableTargetLists = []
            return
        }
        do {
            availableTargetLists = try await blueskyClient.fetchLists(for: account, appPassword: appPassword)
                .sorted {
                    if $0.kind != $1.kind {
                        return $0.kind == .moderation
                    }
                    return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
                }
        } catch {
            availableTargetLists = []
            AppLogger.moderation.error("Failed to load available target lists: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func loadInitial() async {
        guard let account = searchAccount,
              let appPassword = accountStore.appPassword(for: account) else { return }
        await viewModel.load(account: account, appPassword: appPassword, using: blueskyClient)
    }

    private func loadMore() async {
        guard let account = searchAccount,
              let appPassword = accountStore.appPassword(for: account) else { return }
        guard loadMoreTask == nil else { return }
        let task = Task {
            await viewModel.loadMore(account: account, appPassword: appPassword, using: blueskyClient)
        }
        loadMoreTask = task
        await task.value
        loadMoreTask = nil
    }

    private func refresh() async {
        guard let account = searchAccount,
              let appPassword = accountStore.appPassword(for: account) else { return }
        await viewModel.refresh(account: account, appPassword: appPassword, using: blueskyClient)
    }
}
