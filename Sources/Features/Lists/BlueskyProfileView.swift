import SwiftUI

/// Full profile detail/inspection view for a Bluesky actor.
///
/// Displays profile metadata, follower/following/posts/media stats,
/// moderation controls (block/mute/follow/list membership), block-back
/// functionality (beta), subscribed moderation lists, owned lists,
/// ClearSky lists, handle history, and reporting.
struct BlueskyProfileView: View {
    let member: BlueskyListMember
    let list: BlueskyList?

    @EnvironmentObject private var accountStore: AccountStore
    @EnvironmentObject private var container: BlueskyServiceContainerWrapper
    @EnvironmentObject private var workspaceStore: ModerationWorkspaceStore
    @EnvironmentObject private var chatStore: ChatStore
    @EnvironmentObject private var localizationManager: LocalizationManager
    @EnvironmentObject private var clearskyHeartbeat: ClearskyHeartbeatService
    @EnvironmentObject var internalListStore: InternalListStore
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel = BlueskyProfileViewModel()
    @State private var actionsVM: BlueskyProfileActionsViewModel? = nil

    // MARK: - Properties

    @State private var isShowingAvatarPreview = false // Full-screen avatar overlay
    @State private var showPostBrowser = false // Posts browser sheet
    @State private var showMediaBrowser = false // Media browser sheet
    @State private var shareFileURL: URL?
    @State private var loadTask: Task<Void, Never>?
    @State private var moderationTask: Task<Void, Never>?
    @State private var exportTask: Task<Void, Never>?
    @State private var blockedAccessType: BlockedAccessType? // Blocked-access info sheet
    @State private var showBlockBackConfirm1 = false
    @State private var showBlockBackConfirm2 = false
    @State private var showManagePosts = false
    @State private var showExportSheet = false
    @State private var downloadFormat: ExportFileFormat = .csv
    @State private var isExportActive = false
    @State private var showClearskyLists = false
    @State private var showOwnedLists = false
    @State private var reportReasonText = ""
    @State private var searchAccount: AppAccount?
    @State private var showCreateModerationList = false
    @State private var showCreateRegularList = false
    @State private var showModerationListsHelp = false
    @State private var showListsHelp = false
    @State private var pendingCreateKind: BlueskyList.Kind?
    @State private var showCreateInternalList = false
    @State private var newInternalListName = ""
    @State private var newInternalListColor = InternalListColor.blue
    @State private var showBlockingListsPanel = false
    @State private var showProfileEditor = false

    // MARK: - Computed properties

    /// Returns the preferred search account or falls back to the active account.
    private var preferredSearchAccount: AppAccount? {
        if let prefID = accountStore.preferredSearchAccountID,
           let prefAccount = accountStore.accounts.first(where: { $0.id == prefID })
        {
            prefAccount
        } else {
            accountStore.activeAccount
        }
    }

    /// Identifies whether the user tried to access posts or media that are
    /// blocked by the target account.
    enum BlockedAccessType: String, Identifiable {
        case posts
        case media
        var id: String {
            rawValue
        }
    }

    // MARK: - Body

    var body: some View {
        Group {
            if let account = accountStore.activeAccount,
               let appPassword = accountStore.appPassword(for: account)
            {
                content(account: account, appPassword: appPassword)
            } else {
                ContentUnavailableView(
                    loc("list.detail.missing_creds"),
                    systemImage: "key.slash",
                    description: Text(loc: "list.detail.missing_creds.desc")
                )
            }
        }
        .pageTitle(member.actor.handle)
        .overlay {
            if isShowingAvatarPreview, let avatarURL = viewModel.profile?.avatarURL {
                Color.black.opacity(0.9)
                    .ignoresSafeArea()
                    .onTapGesture { isShowingAvatarPreview = false }
                    .overlay {
                        AsyncImage(url: avatarURL) { image in
                            image
                                .resizable()
                                .scaledToFit()
                                .padding(40)
                        } placeholder: {
                            ProgressView()
                                .tint(.white)
                        }
                    }
                    .overlay(alignment: .topTrailing) {
                        Button {
                            isShowingAvatarPreview = false
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.title)
                                .foregroundStyle(.white.opacity(0.8))
                                .padding()
                        }
                    }
                    .transition(.opacity.animation(UIAccessibility.isReduceMotionEnabled ? nil : .easeInOut))
            }
        }
        .sheet(isPresented: $showPostBrowser) {
            if let profile = viewModel.profile {
                UserPostsView(
                    did: profile.did,
                    displayName: profile.displayName ?? profile.handle,
                    searchAccount: preferredSearchAccount
                )
                .environmentObject(accountStore)
                .environmentObject(container.blueskyClient)
            }
        }
        .sheet(isPresented: $showManagePosts) {
            ManagePostsView(did: member.actor.did)
                .environmentObject(accountStore)
                .environmentObject(container.blueskyClient)
        }
        .sheet(item: $shareFileURL) { url in
            ShareSheet(activityItems: [url])
        }
        .sheet(isPresented: $showExportSheet) {
            NavigationStack {
                VStack(spacing: 20) {
                    if let error = viewModel.exportError {
                        ContentUnavailableView(
                            label: { Label(loc("list.detail.alert_title"), systemImage: "exclamationmark.triangle") },
                            description: { Text(error) }
                        )
                    } else if isExportActive || viewModel.isExportingPosts {
                        ProgressView()
                            .scaleEffect(1.5)
                            .padding(.top, 40)
                        if let label = viewModel.exportProgressLabel {
                            Text(label)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        Button(loc("actions.cancel"), role: .destructive) {
                            exportTask?.cancel()
                            exportTask = nil
                            showExportSheet = false
                        }
                        .buttonStyle(.bordered)
                    } else {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 48))
                            .foregroundStyle(.green)
                        Text(loc("profile.export.complete"))
                            .font(.headline)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .navigationTitle(loc("profile.export.download_posts"))
                .toolbarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        ToolbarCloseButton()
                    }
                }
            }
            .presentationDetents([.height(260)])
        }
        .sheet(isPresented: $showMediaBrowser) {
            if let profile = viewModel.profile {
                MediaBrowserView(did: profile.did, handle: profile.handle)
                    .environmentObject(accountStore)
                    .environmentObject(container.blueskyClient)
            }
        }
        .sheet(isPresented: $showClearskyLists) {
            ClearskyListsView(entries: viewModel.clearskyLists)
                .environmentObject(accountStore)
                .environmentObject(container.blueskyClient)
        }
        .sheet(isPresented: $showOwnedLists) {
            NavigationStack {
                if let ownedLists = viewModel.ownedLists {
                    if ownedLists.isEmpty {
                        ContentUnavailableView(loc("profile.stats.owned_lists.empty"), systemImage: "list.bullet", description: Text(loc: "profile.stats.owned_lists.empty_desc"))
                    } else {
                        List {
                            ForEach(ownedLists) { list in
                                NavigationLink {
                                    ListDetailView(
                                        list: list,
                                        onListUpdated: { _ in }
                                    )
                                    .environmentObject(accountStore)
                                    .environmentObject(container.blueskyClient)
                                    .environmentObject(workspaceStore)
                                } label: {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(list.name).font(.subheadline.weight(.semibold))
                                        Text(list.kind.title).font(.caption).foregroundStyle(.secondary)
                                        if let count = list.memberCount {
                                            Text(loc("profile.stats.owned_lists.member_count").replacingOccurrences(of: "{count}", with: "\(count)")).font(.caption).foregroundStyle(.secondary)
                                        }
                                    }
                                    .padding(.vertical, 2)
                                }
                            }
                        }
                        .listStyle(.insetGrouped)
                    }
                } else {
                    ProgressView()
                }
            }
            .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $viewModel.showReportSheet) {
            if let account = accountStore.activeAccount,
               let appPassword = accountStore.appPassword(for: account)
            {
                SimplifiedReportSheet(
                    title: loc("profile.report"),
                    selectedReason: $viewModel.selectedReportReason,
                    evidenceText: $reportReasonText,
                    isSubmitting: viewModel.isReporting,
                    makeSupportDraft: { makeProfileSupportDraft(for: viewModel.profile) },
                    onCancel: {
                        viewModel.showReportSheet = false
                    },
                    onSubmit: {
                        viewModel.showReportSheet = false
                        Task {
                            await viewModel.reportAccount(
                                reason: reportReasonText.nilIfBlank,
                                account: account,
                                appPassword: appPassword,
                                using: container.blueskyClient
                            )
                        }
                    }
                )
            }
        }
        .sheet(item: $blockedAccessType) { type in
            NavigationStack {
                VStack(spacing: 24) {
                    Spacer()

                    Image(systemName: "hand.raised.slash.fill")
                        .font(.system(size: 64))
                        .foregroundStyle(.red)
                        .symbolRenderingMode(.hierarchical)

                    VStack(spacing: 8) {
                        Text(loc: "profile.blocked.title")
                            .font(.title2.weight(.bold))
                        Text(loc: "profile.blocked.\(type.rawValue)_desc")
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.horizontal, 32)

                    Spacer()
                }
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(loc("actions.got_it")) { blockedAccessType = nil }
                    }
                }
            }
            .presentationDetents([.height(320)])
        }
        .sheet(isPresented: $showCreateModerationList) {
            if let sheetAccount = accountStore.activeAccount,
               let sheetAppPassword = accountStore.appPassword(for: sheetAccount)
            {
                ListMetadataSheet(mode: .create(kind: .moderation)) { name, description, _ in
                    Task {
                        await viewModel.createListAndAddActor(
                            name: name,
                            description: description,
                            kind: .moderation,
                            account: sheetAccount,
                            appPassword: sheetAppPassword,
                            using: container.blueskyClient
                        )
                    }
                }
                .environmentObject(accountStore)
                .environmentObject(container.blueskyClient)
            }
        }
        .sheet(isPresented: $showCreateRegularList) {
            if let sheetAccount = accountStore.activeAccount,
               let sheetAppPassword = accountStore.appPassword(for: sheetAccount)
            {
                ListMetadataSheet(mode: .create(kind: .regular)) { name, description, _ in
                    Task {
                        await viewModel.createListAndAddActor(
                            name: name,
                            description: description,
                            kind: .regular,
                            account: sheetAccount,
                            appPassword: sheetAppPassword,
                            using: container.blueskyClient
                        )
                    }
                }
                .environmentObject(accountStore)
                .environmentObject(container.blueskyClient)
            }
        }
        .sheet(isPresented: $showCreateInternalList) {
            NavigationStack {
                Form {
                    Section {
                        TextField(loc("internal.lists.name"), text: $newInternalListName)
                        Picker(loc("internal.lists.color"), selection: $newInternalListColor) {
                            ForEach(InternalListColor.allCases, id: \.self) { color in
                                HStack {
                                    Circle()
                                        .fill(color.colorValue)
                                        .frame(width: 16, height: 16)
                                    Text(color.rawValue.capitalized)
                                }
                                .tag(color)
                            }
                        }
                        .pickerStyle(.navigationLink)
                    }
                }
                .navigationTitle(loc("internal.lists.create"))
                .toolbarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(loc("actions.save")) {
                            internalListStore.addList(name: newInternalListName, color: newInternalListColor)
                            newInternalListName = ""
                            newInternalListColor = .blue
                            showCreateInternalList = false
                        }
                        .disabled(newInternalListName.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                    ToolbarItem(placement: .cancellationAction) {
                        Button(loc("actions.cancel")) {
                            newInternalListName = ""
                            showCreateInternalList = false
                        }
                    }
                }
            }
            .presentationDetents([.medium])
        }
        .sheet(isPresented: $showModerationListsHelp) {
            helpSheet(
                title: loc("profile.on_my_moderation_lists"),
                text: loc("profile.on_my_moderation_lists.help")
            )
        }
        .sheet(isPresented: $showListsHelp) {
            helpSheet(
                title: loc("profile.on_my_lists"),
                text: loc("profile.on_my_lists.help")
            )
        }
        .sheet(isPresented: $showBlockingListsPanel) {
            NavigationStack {
                List {
                    Section(loc("profile.blocking_lists.section_header")) {
                        ForEach(viewModel.blockingLists) { info in
                            if let uri = info.listURI {
                                NavigationLink {
                                    ListDetailView(
                                        list: BlueskyList(id: uri, name: info.name, description: "", memberCount: info.memberCount, kind: .moderation),
                                        onListUpdated: { _ in }
                                    )
                                    .environmentObject(accountStore)
                                    .environmentObject(container.blueskyClient)
                                    .environmentObject(workspaceStore)
                                } label: {
                                    Text(info.name)
                                }
                            } else {
                                Text(info.name)
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)
                .navigationTitle(loc("profile.blocking_lists.panel_title"))
                .toolbarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        ToolbarCloseButton()
                    }
                }
            }
        }
        .sheet(isPresented: $showProfileEditor) {
            if let account = accountStore.activeAccount,
               let password = accountStore.appPassword(for: account)
            {
                ProfileEditView(account: account, appPassword: password)
                    .environmentObject(accountStore)
                    .environmentObject(container.blueskyClient)
            }
        }
        .confirmationDialog(
            loc("profile.create_list_confirm.title"),
            isPresented: Binding(
                get: { pendingCreateKind != nil },
                set: {
                    if !$0 {
                        pendingCreateKind = nil
                    }
                }
            ),
            titleVisibility: .visible
        ) {
            Button(loc("profile.create_list_confirm.create")) {
                if pendingCreateKind == .moderation {
                    showCreateModerationList = true
                } else {
                    showCreateRegularList = true
                }
                pendingCreateKind = nil
            }
            Button(loc("actions.cancel"), role: .cancel) {
                pendingCreateKind = nil
            }
        }
    }

    // swiftlint:disable:next function_body_length cyclomatic_complexity
    // MARK: - Content

    /// The account used for data-fetching (preferred search or active).
    private var dataAccount: AppAccount? {
        preferredSearchAccount ?? accountStore.activeAccount
    }

    /// The app password for `dataAccount`.
    private var dataAppPassword: String? {
        dataAccount.flatMap { accountStore.appPassword(for: $0) }
    }

    private func content(account: AppAccount, appPassword: String) -> some View {
        List {
            if let profile = viewModel.profile {
                Section {
                    VStack(alignment: .leading, spacing: 0) {
                        if let bannerURL = profile.bannerURL {
                            // Banner with avatar overlapping bottom-left
                            ZStack(alignment: .bottomLeading) {
                                profileBanner(url: bannerURL)

                                // Avatar overlapping bottom of banner (half on banner, half below)
                                profileAvatar(for: profile)
                                    .offset(y: 36)
                                    .padding(.leading, 16)
                            }

                            // Info below banner+avatar (offset for overlapping avatar)
                            VStack(alignment: .leading, spacing: 16) {
                                HStack(spacing: 14) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(profile.title)
                                            .appFont(.heading)
                                        Text(profile.handle)
                                            .font(.subheadline)
                                            .foregroundStyle(.secondary)
                                    }
                                }

                                if let description = profile.description, !description.isEmpty {
                                    Text(description)
                                        .appFont(.body)
                                }

                                if !isOwnProfile, let state = profile.viewerState {
                                    relationshipBadges(state: state, blockingListNames: viewModel.combinedBlockingNames)
                                }

                                if isOwnProfile {
                                    Button {
                                        showProfileEditor = true
                                    } label: {
                                        HStack {
                                            Spacer()
                                            Text(loc("profile.edit.title"))
                                            Spacer()
                                        }
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .controlSize(.small)
                                }
                            }
                            .padding(.horizontal)
                            .padding(.vertical, 12)
                            .padding(.top, 36)
                        } else {
                            // No banner: inline avatar layout
                            VStack(alignment: .leading, spacing: 16) {
                                HStack(spacing: 14) {
                                    profileAvatar(for: profile)

                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(profile.title)
                                            .appFont(.heading)
                                        Text(profile.handle)
                                            .font(.subheadline)
                                            .foregroundStyle(.secondary)
                                    }
                                }

                                if let description = profile.description, !description.isEmpty {
                                    Text(description)
                                        .appFont(.body)
                                }

                                if !isOwnProfile, let state = profile.viewerState {
                                    relationshipBadges(state: state, blockingListNames: viewModel.combinedBlockingNames)
                                }

                                if isOwnProfile {
                                    Button {
                                        showProfileEditor = true
                                    } label: {
                                        HStack {
                                            Spacer()
                                            Text(loc("profile.edit.title"))
                                            Spacer()
                                        }
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .controlSize(.small)
                                }
                            }
                            .padding(.horizontal)
                            .padding(.vertical, 12)
                        }
                    }
                }
                .listRowInsets(EdgeInsets())

                Section {
                    NavigationLink {
                        RelationshipsView(mode: .followers, initialCount: profile.followersCount, profileDID: profile.did, profileHandle: profile.handle)
                    } label: {
                        HStack {
                            Text(loc: "profile.stats.followers")
                            Spacer()
                            Text(statText(profile.followersCount))
                                .foregroundStyle(.secondary)
                        }
                    }
                    NavigationLink {
                        RelationshipsView(mode: .following, initialCount: profile.followsCount, profileDID: profile.did, profileHandle: profile.handle)
                    } label: {
                        HStack {
                            Text(loc: "profile.stats.following")
                            Spacer()
                            Text(statText(profile.followsCount))
                                .foregroundStyle(.secondary)
                        }
                    }
                    Button {
                        showPostBrowser = true
                    } label: {
                        HStack {
                            Text(loc: "profile.stats.posts")
                            Spacer()
                            Text(statText(profile.postsCount))
                                .foregroundStyle(.secondary)
                            Image(systemName: "chevron.right")
                                .flipsForRightToLeftLayoutDirection(true)
                                .appFont(.subheading)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                    Menu {
                        Button {
                            guard let dataAccount, let dataPassword = dataAppPassword else { return }
                            downloadFormat = .csv
                            isExportActive = true
                            showExportSheet = true
                            runExport(.csv, account: dataAccount, appPassword: dataPassword)
                        } label: {
                            Label { Text(loc: "profile.export.csv") } icon: { Image(systemName: "arrow.down.doc") }
                        }
                        Button {
                            guard let dataAccount, let dataPassword = dataAppPassword else { return }
                            downloadFormat = .json
                            isExportActive = true
                            showExportSheet = true
                            runExport(.json, account: dataAccount, appPassword: dataPassword)
                        } label: {
                            Label { Text(loc: "profile.export.json") } icon: { Image(systemName: "arrow.down.doc") }
                        }
                    } label: {
                        HStack {
                            Text(loc: "profile.export.download_posts")
                            Spacer()
                            Image(systemName: "arrow.down.doc")
                                .foregroundStyle(.secondary)
                            Image(systemName: "chevron.right")
                                .flipsForRightToLeftLayoutDirection(true)
                                .appFont(.subheading)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                    Button {
                        if profile.viewerState?.blockedBy == true,
                           preferredSearchAccount?.id == accountStore.activeAccountID
                        {
                            // Only block if the preferred search account is the same as the
                            // active (blocked) viewer. If a different preferred search account
                            // is configured, let the media browser use it to fetch data.
                            blockedAccessType = .media
                        } else {
                            showMediaBrowser = true
                        }
                    } label: {
                        HStack {
                            Text(loc: "profile.stats.media")
                            Spacer()
                            if viewModel.isScanningMedia {
                                ProgressView()
                                    .scaleEffect(0.6)
                            } else if viewModel.mediaImageCount > 0 || viewModel.mediaVideoCount > 0 {
                                Text([
                                    viewModel.mediaImageCount > 0 ? "\(viewModel.mediaImageCount) image\(viewModel.mediaImageCount != 1 ? "s" : "")" : nil,
                                    viewModel.mediaVideoCount > 0 ? "\(viewModel.mediaVideoCount) video\(viewModel.mediaVideoCount != 1 ? "s" : "")" : nil,
                                ].compactMap(\.self).joined(separator: " · "))
                                    .foregroundStyle(.secondary)
                                Image(systemName: "chevron.right")
                                    .flipsForRightToLeftLayoutDirection(true)
                                    .appFont(.subheading)
                                    .foregroundStyle(.secondary)
                            } else if !viewModel.isScanningMedia {
                                Text(loc: "profile.media.empty")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    Button {
                        showClearskyLists = true
                    } label: {
                        HStack {
                            Text(loc: "profile.stats.lists")
                            Spacer()
                            if viewModel.isFetchingLists {
                                ProgressView()
                                    .scaleEffect(0.6)
                            } else if !viewModel.clearskyLists.isEmpty {
                                Text("\(viewModel.clearskyLists.count)")
                                    .foregroundStyle(.secondary)
                                Image(systemName: "chevron.right")
                                    .flipsForRightToLeftLayoutDirection(true)
                                    .appFont(.subheading)
                                    .foregroundStyle(.secondary)
                            } else if viewModel.listError == nil, !viewModel.isLoading {
                                ProgressView()
                                    .scaleEffect(0.6)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    Button {
                        showOwnedLists = true
                    } label: {
                        HStack {
                            Text(loc: "profile.stats.owned_lists")
                            Spacer()
                            if viewModel.isFetchingOwnedLists {
                                ProgressView()
                                    .scaleEffect(0.6)
                            } else if let owned = viewModel.ownedLists {
                                Text("\(owned.count)")
                                    .foregroundStyle(.secondary)
                                Image(systemName: "chevron.right")
                                    .flipsForRightToLeftLayoutDirection(true)
                                    .appFont(.subheading)
                                    .foregroundStyle(.secondary)
                            } else if !viewModel.isLoading {
                                ProgressView()
                                    .scaleEffect(0.6)
                            }
                        }
                    }
                    .buttonStyle(.plain)

                    if let error = viewModel.listError {
                        HStack {
                            Spacer()
                            Text(error)
                                .font(.caption)
                                .foregroundStyle(.red)
                                .lineLimit(1)
                        }
                    }
                } header: {
                    Text(loc("profile.stats"))
                        .onTapGesture(count: 2) { showPostBrowser = true }
                }

                if !isOwnProfile {
                    Section {
                        if let viewerState = profile.viewerState {
                            Toggle(isOn: Binding(
                                get: { viewModel.pendingFollowingState ?? viewerState.isFollowing },
                                set: { _ in
                                    runModeration {
                                        await viewModel.toggleFollow(
                                            account: account,
                                            appPassword: appPassword,
                                            using: container.blueskyClient
                                        )
                                    }
                                }
                            )) {
                                Label { Text(loc: "profile.following") } icon: { Image(systemName: "person.badge.plus") }
                            }
                            .disabled(viewModel.isUpdatingModeration)

                            Toggle(isOn: Binding(
                                get: { viewModel.pendingBlockState ?? viewerState.isBlocking },
                                set: { _ in
                                    runModeration {
                                        await viewModel.toggleBlock(
                                            account: account,
                                            appPassword: appPassword,
                                            using: container.blueskyClient
                                        )
                                    }
                                }
                            )) {
                                Label { Text(loc: "profile.block") } icon: { Image(systemName: "hand.raised") }
                            }
                            .disabled(viewModel.isUpdatingModeration || viewModel.isBlockedByList)
                            .accessibilityHint(viewerState.isBlocking ? loc("profile.unblock.hint") : loc("profile.block.hint"))
                            if viewModel.isBlockedByList {
                                let displayText = Self.formattedBlockingList(viewModel.combinedBlockingNames)
                                Text(displayText)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .listRowInsets(EdgeInsets(top: 0, leading: 48, bottom: 0, trailing: 0))
                            }

                            Toggle(isOn: Binding(
                                get: { viewModel.pendingMuteState ?? viewerState.muted },
                                set: { _ in
                                    runModeration {
                                        await viewModel.toggleMute(
                                            account: account,
                                            appPassword: appPassword,
                                            using: container.blueskyClient
                                        )
                                    }
                                }
                            )) {
                                Label { Text(loc: "profile.mute") } icon: { Image(systemName: "speaker.slash") }
                            }
                            .disabled(viewModel.isUpdatingModeration)
                            .accessibilityHint(viewerState.muted ? loc("profile.unmute.hint") : loc("profile.mute.hint"))
                        }

                        if let statusMessage = viewModel.statusMessage {
                            Text(statusMessage)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } header: {
                        Text(loc: "profile.moderation_section")
                    }
                }

                if !isOwnProfile {
                    let moderationMemberships = viewModel.listMemberships.filter { $0.kind == .moderation }
                    let regularMemberships = viewModel.listMemberships.filter { $0.kind == .regular }

                    Section {
                        if viewModel.isFetchingMemberships {
                            ProgressView()
                                .scaleEffect(0.6)
                        } else {
                            ForEach(moderationMemberships) { membership in
                                HStack {
                                    Toggle(isOn: Binding(
                                        get: { viewModel.pendingListMemberStates[membership.listURI] ?? membership.isMember },
                                        set: { _ in
                                            runModeration {
                                                await viewModel.toggleListMembership(
                                                    membership,
                                                    account: account,
                                                    appPassword: appPassword,
                                                    using: container.blueskyClient
                                                )
                                            }
                                        }
                                    )) {
                                        Text(membership.name)
                                    }
                                    .disabled(viewModel.isUpdatingListMembership)
                                    if let count = membership.memberCount {
                                        Text("(\(count))")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    } header: {
                        HStack {
                            Text(loc: "profile.on_my_moderation_lists")
                            HelpInfoButton(
                                action: { showModerationListsHelp = true },
                                accessibilityLabel: loc("profile.on_my_moderation_lists")
                            )
                            Spacer()
                            Button {
                                pendingCreateKind = .moderation
                            } label: {
                                Image(systemName: "plus")
                                    .font(.subheadline.weight(.semibold))
                                    .accessibilityLabel(loc("profile.create_moderation_list"))
                            }
                            .disabled(viewModel.isCreatingList)
                        }
                    }

                    Section {
                        if viewModel.isFetchingMemberships {
                            ProgressView()
                                .scaleEffect(0.6)
                        } else {
                            ForEach(regularMemberships) { membership in
                                HStack {
                                    Toggle(isOn: Binding(
                                        get: { viewModel.pendingListMemberStates[membership.listURI] ?? membership.isMember },
                                        set: { _ in
                                            runModeration {
                                                await viewModel.toggleListMembership(
                                                    membership,
                                                    account: account,
                                                    appPassword: appPassword,
                                                    using: container.blueskyClient
                                                )
                                            }
                                        }
                                    )) {
                                        Text(membership.name)
                                    }
                                    .disabled(viewModel.isUpdatingListMembership)
                                    if let count = membership.memberCount {
                                        Text("(\(count))")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    } header: {
                        HStack {
                            Text(loc: "profile.on_my_lists")
                            HelpInfoButton(
                                action: { showListsHelp = true },
                                accessibilityLabel: loc("profile.on_my_lists")
                            )
                            Spacer()
                            Button {
                                pendingCreateKind = .regular
                            } label: {
                                Image(systemName: "plus")
                                    .font(.subheadline.weight(.semibold))
                                    .accessibilityLabel(loc("profile.create_regular_list"))
                            }
                            .disabled(viewModel.isCreatingList)
                        }
                    }

                    Section {
                        let memberDID = member.actor.did
                        let handle = member.actor.handle
                        let name = member.actor.displayName
                        let avatar = member.actor.avatarURL?.absoluteString
                        if !internalListStore.lists.isEmpty {
                            ForEach(internalListStore.lists) { list in
                                let isOnList = internalListStore.isMember(did: memberDID, in: list.id)
                                Toggle(isOn: Binding(
                                    get: { isOnList },
                                    set: { newValue in
                                        if newValue {
                                            internalListStore.addMember(did: memberDID, handle: handle, displayName: name, avatarURL: avatar, to: list.id)
                                        } else {
                                            internalListStore.removeMember(did: memberDID, from: list.id)
                                        }
                                    }
                                )) {
                                    HStack(spacing: 8) {
                                        Circle()
                                            .fill(list.color.colorValue)
                                            .frame(width: 10, height: 10)
                                        Text(list.name)
                                    }
                                }
                            }
                        }
                    } header: {
                        HStack {
                            Text(loc("internal.profile.section"))
                            Spacer()
                            Button {
                                showCreateInternalList = true
                            } label: {
                                Image(systemName: "plus")
                                    .font(.subheadline.weight(.semibold))
                                    .accessibilityLabel(loc("internal.lists.create"))
                            }
                        }
                    }
                }

                if let profileURL = profile.profileURL {
                    Section {
                        Link(destination: profileURL) {
                            Label { Text(loc: "profile.open_bluesky") } icon: { Image(systemName: "arrow.up.right.square") }
                        }
                        .accessibilityHint(loc("profile.open_bluesky.hint"))
                    }
                }

                Section {
                    LabeledContent {
                        HStack(spacing: 4) {
                            Text(profile.handle)
                                .lineLimit(1)
                            Button {
                                UIPasteboard.general.string = profile.handle
                                viewModel.statusMessage = String.localized("profile.status.handle_copied")
                            } label: {
                                Image(systemName: "doc.on.doc")
                                    .font(.caption)
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.secondary)
                        }
                    } label: {
                        Text(loc: "profile.stats.handle")
                    }
                    LabeledContent {
                        HStack(spacing: 4) {
                            Text(profile.did)
                                .lineLimit(1)
                                .font(.caption.monospaced())
                            Button {
                                UIPasteboard.general.string = profile.did
                                viewModel.statusMessage = String.localized("profile.status.did_copied")
                            } label: {
                                Image(systemName: "doc.on.doc")
                                    .font(.caption)
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.secondary)
                        }
                    } label: {
                        Text(loc: "profile.stats.did")
                    }
                    if let createdAt = profile.createdAt {
                        LabeledContent("profile.stats.joined", value: createdAt.formatted(date: .abbreviated, time: .omitted))
                    }
                    if !profile.labels.isEmpty {
                        LabeledContent("profile.stats.labels", value: profile.labels.map(localizedLabel).joined(separator: ", "))
                    }
                } header: {
                    Text(loc: "profile.account_info")
                }

                if !viewModel.handleHistory.isEmpty {
                    Section {
                        ForEach(viewModel.handleHistory) { entry in
                            HStack {
                                Text(entry.handle)
                                    .font(.caption.monospaced())
                                if entry.isCurrent {
                                    Text(loc: "profile.current_badge")
                                        .font(.caption2.weight(.semibold))
                                        .foregroundStyle(.white)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 3)
                                        .background(Capsule().fill(.green))
                                }
                                Spacer()
                                Text(entry.date.formatted(date: .abbreviated, time: .omitted))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    } header: {
                        Text(loc: "profile.handle_history")
                    }
                }

                if !isOwnProfile {
                    Section {
                        Button {
                            viewModel.selectedReportReason = .simplifiedDefault
                            reportReasonText = ""
                            viewModel.showReportSheet = true
                        } label: {
                            Label(loc("profile.report"), systemImage: "exclamationmark.shield")
                        }
                        .disabled(viewModel.isReporting)
                        .accessibilityHint(loc("profile.report.hint"))

                        if let list {
                            Label { Text(verbatim: loc("profile.member_of").replacingOccurrences(of: "{list}", with: list.name)) } icon: { Image(systemName: "person.2.badge.gearshape") }
                                .foregroundStyle(.secondary)
                        }

                        let isBlockingThem = profile.viewerState?.isBlocking == true || (profile.viewerState?.blockingByListName.isEmpty == false)
                        let isBlockedByThem = profile.viewerState?.blockedBy == true
                        let isMutualFollow = profile.viewerState?.isFollowing == true && profile.viewerState?.followsYou == true
                        let shouldDisableDM = isBlockingThem || isBlockedByThem || isMutualFollow
                        Button {
                            Task {
                                chatStore.setAccount(account, appPassword: appPassword)
                                if let convo = await chatStore.getOrCreateConvo(memberDID: member.actor.did) {
                                    workspaceStore.pendingChatConversation = convo
                                    workspaceStore.selectedTab = .chat
                                    dismiss()
                                }
                            }
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "bubble.left.and.bubble.right")
                                Text(loc: "profile.direct_message")
                                Text(loc: "profile.beta")
                                    .font(.caption2.weight(.bold))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 2)
                                    .background(Capsule().fill(.orange))
                            }
                        }
                        .disabled(shouldDisableDM)
                        if isBlockingThem {
                            Text(loc("profile.dm_blocked_notice"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else if isBlockedByThem {
                            Text(loc("profile.dm_blocked_by_notice"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else if isMutualFollow {
                            Text(loc("profile.dm_mutual_notice"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                    } header: {
                        Text(loc: "profile.actions_section")
                    }
                }

                if isOwnProfile {
                    Section {
                        if !clearskyHeartbeat.isClearskyAvailable {
                            ClearskyBanner()
                        } else {
                            // Blocking count
                            HStack {
                                Text(loc: "profile.block_back.blocking")
                                Spacer()
                                if actionsVM?.isFetchingBlocking ?? false {
                                    ProgressView().scaleEffect(0.7)
                                } else {
                                    Text(BlueskyProfileActionsViewModel.countText(actionsVM?.blockingCount))
                                        .foregroundStyle(.secondary)
                                }
                            }
                            // Blocked by count
                            HStack {
                                Text(loc: "profile.block_back.blocked_by")
                                Spacer()
                                if actionsVM?.isFetchingBlockedBy ?? false {
                                    ProgressView().scaleEffect(0.7)
                                } else {
                                    Text(BlueskyProfileActionsViewModel.countText(actionsVM?.blockedByCount))
                                        .foregroundStyle(.secondary)
                                }
                            }

                            Button {
                                Task { await actionsVM?.fetchBlockPreview() ?? () }
                            } label: {
                                HStack {
                                    HStack {
                                        Text(loc: "profile.block_back.unblocked")
                                        Spacer()
                                        if actionsVM?.isFetchingUnblocked ?? false {
                                            ProgressView().scaleEffect(0.7)
                                        } else {
                                            Text(BlueskyProfileActionsViewModel.countText(actionsVM?.unblockedBlockersCount))
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                    if actionsVM?.blockBackPreviewAvailable ?? false {
                                        Image(systemName: "chevron.right")
                                            .flipsForRightToLeftLayoutDirection(true)
                                            .appFont(.subheading)
                                            .foregroundStyle(Color.skyPrimary.opacity(0.8))
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                            .disabled(!(actionsVM?.blockBackPreviewAvailable ?? false))

                            if actionsVM?.isBlockingBack ?? false, actionsVM?.blockBackTotal ?? 0 > 0 {
                                VStack(spacing: 8) {
                                    ProgressView(value: Double(actionsVM?.blockBackCompleted ?? 0), total: Double(actionsVM?.blockBackTotal ?? 0))
                                        .progressViewStyle(.linear)
                                        .tint(actionsVM?.blockBackFailureCount ?? 0 > 0 ? Color.orange : Color.skyPrimary)
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
                                            .foregroundStyle(.green)
                                        if actionsVM?.blockBackFailureCount ?? 0 > 0 {
                                            Label("\(actionsVM?.blockBackFailureCount ?? 0)", systemImage: "xmark.circle.fill")
                                                .font(.caption)
                                                .foregroundStyle(.red)
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
                                .padding(.vertical, 4)
                                .animation(.default.speed(1.5), value: actionsVM?.blockBackCurrentHandle)
                            } else if actionsVM?.isBlockingBack ?? false {
                                HStack(spacing: 8) {
                                    ProgressView()
                                        .scaleEffect(0.7)
                                    Text(loc("profile.block_back.preparing"))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                .padding(.vertical, 4)
                            } else if actionsVM?.showBlockBackResult ?? false {
                                HStack(spacing: 8) {
                                    if actionsVM?.blockBackFailureCount ?? 0 == 0 {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(.green)
                                    } else {
                                        Image(systemName: "exclamationmark.triangle.fill")
                                            .foregroundStyle(.orange)
                                    }
                                    Text(actionsVM?.blockBackResultSummary ?? "")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                                .padding(.vertical, 4)
                            } else if let blockedBy = actionsVM?.blockedByCount,
                                      let unblocked = actionsVM?.unblockedBlockersCount
                            {
                                if blockedBy == 0 {
                                    Label(loc("profile.block_back.none_blocking"), systemImage: "checkmark.circle.fill")
                                        .foregroundStyle(.green)
                                } else if unblocked == 0 {
                                    Label(loc("profile.block_back.all_clear"), systemImage: "checkmark.circle.fill")
                                        .foregroundStyle(.green)
                                }
                            }
                        }

                        if let error = actionsVM?.blockBackError {
                            Text(error)
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                    } header: {
                        HStack(spacing: 6) {
                            Text(loc: "profile.block_back.section")
                            Text(loc: "profile.beta")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(Color.orange, in: RoundedRectangle(cornerRadius: 4))
                        }
                    }
                }

                if isOwnProfile {
                    let moderationSubscriptions = (viewModel.subscribedLists ?? []).filter { $0.kind == .moderation }

                    Section {
                        if viewModel.isFetchingSubscribedLists {
                            HStack {
                                ProgressView()
                                    .scaleEffect(0.7)
                                Text(loc("profile.subscribed_lists.loading"))
                                    .foregroundStyle(.secondary)
                            }
                        } else if moderationSubscriptions.isEmpty {
                            Text(loc("profile.subscribed_lists.empty"))
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(moderationSubscriptions) { sub in
                                NavigationLink {
                                    ListDetailView(
                                        list: BlueskyList(id: sub.listURI, name: sub.name, description: sub.description ?? "", memberCount: sub.memberCount, kind: sub.kind),
                                        onListUpdated: { _ in }
                                    )
                                    .environmentObject(accountStore)
                                    .environmentObject(container.blueskyClient)
                                    .environmentObject(workspaceStore)
                                } label: {
                                    VStack(alignment: .leading, spacing: 2) {
                                        HStack {
                                            Text(sub.name)
                                                .lineLimit(1)
                                            Spacer()
                                            if let subscribedAt = sub.subscribedAt {
                                                Text(formatDateRelative(dateString: subscribedAt))
                                                    .font(.caption)
                                                    .foregroundStyle(.secondary)
                                            }
                                        }
                                        if let desc = sub.description, !desc.isEmpty {
                                            Text(desc)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                                .lineLimit(2)
                                        }
                                        HStack(spacing: 4) {
                                            Text(sub.ownerHandle)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                            if let count = sub.memberCount {
                                                Text("·")
                                                    .font(.caption)
                                                    .foregroundStyle(.secondary)
                                                Text(loc("profile.subscribed_lists.member_count").replacingOccurrences(of: "{count}", with: "\(count)"))
                                                    .font(.caption)
                                                    .foregroundStyle(.secondary)
                                            }
                                        }
                                    }
                                    .padding(.vertical, 2)
                                }
                            }
                        }
                    } header: {
                        Text(loc("profile.subscribed_lists"))
                    }

                    Section {
                        Button {
                            showManagePosts = true
                        } label: {
                            Label {
                                Text(loc("profile.manage_posts.title"))
                            } icon: {
                                Image(systemName: "pencil.and.list.clipboard")
                            }
                        }
                    }
                }
            } else if viewModel.isLoading {
                LoadingPanel(message: loc("profile.loading"))
            }

            if let errorMessage = viewModel.errorMessage {
                ErrorRetryBanner(message: errorMessage) {
                    viewModel.errorMessage = nil
                    startLoadTask {
                        await viewModel.load(
                            did: member.actor.did,
                            account: account,
                            viewerPassword: appPassword,
                            dataAccount: dataAccount ?? account,
                            dataPassword: dataAppPassword ?? appPassword,
                            using: container.blueskyClient
                        )
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .refreshable {
            let wasOwnProfile = isOwnProfile
            await runLoad {
                await viewModel.load(
                    did: member.actor.did,
                    account: account,
                    viewerPassword: appPassword,
                    dataAccount: dataAccount ?? account,
                    dataPassword: dataAppPassword ?? appPassword,
                    using: container.blueskyClient
                )
            }
            // Fetch block counts in the refreshable's own actor context,
            // not inside runLoad's @Sendable closure (avoids capture issues).
            if wasOwnProfile {
                await actionsVM?.fetchBlockCounts(isOwnProfile: true)
            }
        }
        .task {
            await runLoad {
                await viewModel.loadIfNeeded(
                    did: member.actor.did,
                    viewerAccount: account,
                    viewerPassword: appPassword,
                    dataAccount: dataAccount ?? account,
                    dataPassword: dataAppPassword ?? appPassword,
                    using: container.blueskyClient
                )
            }
        }
        .task {
            wireActionsVM()
        }
        .onDisappear {
            loadTask?.cancel()
            moderationTask?.cancel()
            exportTask?.cancel()
        }
        .task(id: viewModel.profile?.did) {
            searchAccount = preferredSearchAccount
            // Lazy-init actionsVM with real environment objects.
            // No appPassword needed — ClearSky calls are unauthenticated.
            let vm = actionsVM ?? {
                let v = BlueskyProfileActionsViewModel(
                    profileService: container.blueskyClient,
                    clearskyService: container.blueskyClient,
                    accountStore: accountStore,
                    clearskyHeartbeat: clearskyHeartbeat
                )
                actionsVM = v
                return v
            }()
            async let blocks = vm.fetchBlockCounts(isOwnProfile: isOwnProfile)
            if let handle = viewModel.profile?.handle, let did = viewModel.profile?.did {
                async let clearsky = viewModel.fetchClearskyLists(handle: handle, using: container.blueskyClient)
                if let acct = searchAccount, let password = accountStore.appPassword(for: acct) {
                    async let owned = viewModel.fetchOwnedLists(did: did, account: acct, appPassword: password, using: container.blueskyClient)
                    async let subscribed = fetchSubscribedListsIfOwn(account: acct, appPassword: password, targetDID: did)

                    _ = await (blocks, clearsky, owned, subscribed)
                } else {
                    _ = await (blocks, clearsky)
                }
            } else {
                await blocks
            }
        }
        .onChange(of: clearskyHeartbeat.isClearskyAvailable) { _, isAvailable in
            if !isAvailable {
                actionsVM?.resetBlockBackCounts()
            } else if isOwnProfile {
                Task { await actionsVM?.fetchBlockCounts(isOwnProfile: isOwnProfile) }
            }
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
                Task {
                    let actors = actionsVM?.blockPreviewActors ?? []
                    await actionsVM?.blockBack(actors: actors)
                }
            }
        } message: {
            if let count = actionsVM?.unblockedBlockersCount {
                Text(loc("profile.block_back.confirm.second.message").replacingOccurrences(of: "{count}", with: "\(count)"))
            }
        }
        .sheet(isPresented: Binding(
            get: { actionsVM?.showBlockBackPreview ?? false },
            set: {
                if actionsVM != nil {
                    actionsVM!.showBlockBackPreview = $0
                }
            }
        )) {
            blockBackPreviewSheet
        }
    }

    // MARK: - Block back

    private var blockBackPreviewSheet: some View {
        NavigationStack {
            blockBackPreviewContent
        }
    }

    @ViewBuilder
    private var blockBackPreviewContent: some View {
        if actionsVM?.isFetchingBlockPreview ?? false {
            List {
                VStack(spacing: 16) {
                    Spacer()
                    ProgressView()
                        .scaleEffect(1.5)
                    Text(loc("profile.block_back.preview.loading"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }
            .listStyle(.insetGrouped)
            .navigationTitle(loc("profile.block_back.preview.title"))
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    ToolbarCloseButton()
                }
            }
        } else if (actionsVM?.blockPreviewActors ?? []).isEmpty {
            List {
                Text(loc("profile.block_back.preview.empty"))
                    .foregroundStyle(.secondary)
            }
            .listStyle(.insetGrouped)
            .navigationTitle(loc("profile.block_back.preview.title"))
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    ToolbarCloseButton()
                }
            }
        } else {
            blockBackPreviewList
        }
    }

    private var blockBackPreviewList: some View {
        List {
            Section {
                ForEach(actionsVM?.blockPreviewActors ?? []) { actor in
                    blockBackPreviewRow(actor: actor)
                }
            } header: {
                Text(
                    loc("profile.block_back.preview.count")
                        .replacingOccurrences(of: "{count}", with: "\\((actionsVM?.blockPreviewActors ?? []).count)")
                )
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(loc("profile.block_back.preview.title"))
        .toolbarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                ToolbarCloseButton()
            }
            ToolbarItem(placement: .confirmationAction) {
                Button(loc("profile.block_back.action")) {
                    if actionsVM != nil {
                        actionsVM!.showBlockBackPreview = false
                    }
                    // Re-fetch count so the confirmation shows the current state
                    Task { await actionsVM?.fetchBlockCounts(isOwnProfile: isOwnProfile) }
                    showBlockBackConfirm1 = true
                }
                .disabled((actionsVM?.blockPreviewActors ?? []).isEmpty)
            }
        }
    }

    private func blockBackPreviewRow(actor: BlueskyActor) -> some View {
        HStack(spacing: 10) {
            if let avatarURL = actor.avatarURL {
                AsyncImage(url: avatarURL) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    Circle().fill(Color.skyPrimary.opacity(0.16))
                }
                .frame(width: 36, height: 36)
                .clipShape(Circle())
            } else {
                Circle()
                    .fill(Color.skyPrimary.opacity(0.16))
                    .frame(width: 36, height: 36)
                    .overlay {
                        Text(actor.title.prefix(1).uppercased())
                            .font(.headline)
                            .foregroundStyle(Color.skyPrimary)
                    }
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(actor.title)
                    .appFont(.body)
                    .lineLimit(1)
                Text("@\(actor.handle)")
                    .appFont(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Label(loc("profile.block_back.preview.blocks_me"), systemImage: "hand.raised.slash.fill")
                    .font(.caption2)
                    .foregroundStyle(.red)
                Label(loc("profile.block_back.preview.not_blocked"), systemImage: "hand.raised.slash")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Helpers

    private func wireActionsVM() {
        actionsVM?.reconfigure(
            profileService: container.blueskyClient,
            clearskyService: container.blueskyClient,
            accountStore: accountStore
        )
    }

    private func makeProfileSupportDraft(for profile: BlueskyProfile?) -> SupportEmailDraft {
        let reason = viewModel.selectedReportReason.localizedTitle
        let handle = profile?.handle ?? member.actor.handle
        let profileURL = profile?.profileURL?.absoluteString ?? "https://bsky.app/profile/\(member.actor.handle)"
        return SupportEmailDraft(
            subject: "Bluesky Account Report — \(handle)",
            body: SupportEmailDraft.htmlBody(
                intro: "I am reporting the following Bluesky account for review.",
                fields: [
                    ("Handle", "@\(handle)"),
                    ("Display Name", profile?.title ?? member.actor.displayName ?? member.actor.handle),
                    ("DID", profile?.did ?? member.actor.did),
                    ("Profile URL", profileURL),
                    ("Reason", reason),
                    ("Additional Details", reportReasonText.nilIfBlank ?? "—"),
                ],
                footer: "Evidence screenshot attached below if provided."
            )
        )
    }

    private func profileBanner(url: URL) -> some View {
        Color.clear
            .frame(maxWidth: .infinity)
            .frame(height: 200)
            .overlay(
                AsyncImage(url: url) { phase in
                    switch phase {
                    case let .success(image):
                        image
                            .resizable()
                            .scaledToFill()
                    case .failure:
                        Rectangle()
                            .fill(Color(.systemGray5))
                    case .empty:
                        Rectangle()
                            .fill(Color(.systemGray5))
                            .overlay {
                                ProgressView()
                                    .tint(.secondary)
                            }
                    @unknown default:
                        Rectangle()
                            .fill(Color(.systemGray5))
                    }
                }
            )
            .clipped()
    }

    private func profileAvatar(for profile: BlueskyProfile) -> some View {
        Button {
            isShowingAvatarPreview = true
        } label: {
            if let avatarURL = profile.avatarURL {
                ThumbnailImageView(url: avatarURL, maxPixelSize: 144) {
                    avatarPlaceholder(for: profile)
                }
                .scaledToFill()
                .frame(width: 72, height: 72)
                .clipShape(Circle())
                .overlay {
                    Circle()
                        .stroke(Color.white.opacity(0.2), lineWidth: 1)
                }
            } else {
                avatarPlaceholder(for: profile)
            }
        }
    }

    private func avatarPlaceholder(for profile: BlueskyProfile) -> some View {
        Circle()
            .fill(Color.skyPrimary.opacity(0.16))
            .frame(width: 72, height: 72)
            .overlay {
                Text(profile.title.prefix(1).uppercased())
                    .font(.title.weight(.bold))
                    .foregroundStyle(Color.skyPrimary)
            }
    }

    private func statText(_ value: Int?) -> String {
        if let value {
            return "\(value)"
        }

        return "-"
    }

    private var isOwnProfile: Bool {
        guard let profile = viewModel.profile,
              let activeAccount = accountStore.activeAccount else { return false }
        if let activeDID = activeAccount.did, activeDID == profile.did {
            return true
        }
        return activeAccount.handle.lowercased() == profile.handle.lowercased()
    }

    private func fetchSubscribedListsIfOwn(account: AppAccount, appPassword: String, targetDID: String? = nil) async {
        await viewModel.fetchSubscribedLists(account: account, appPassword: appPassword, using: container.blueskyClient, targetDID: targetDID)
    }

    @ViewBuilder
    private func relationshipBadges(state: BlueskyViewerState, blockingListNames: [String]) -> some View {
        let badges = Self.computeBadges(state: state, blockingListNames: blockingListNames)
        if !badges.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(badges.indices, id: \.self) { index in
                    let badge = badges[index]
                    if badge.icon == "list.bullet" {
                        Button {
                            showBlockingListsPanel = true
                        } label: {
                            badgeContent(label: badge.label, icon: badge.icon, color: badge.color)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(badge.label)
                        .accessibilityAddTraits(.isButton)
                    } else {
                        badgeContent(label: badge.label, icon: badge.icon, color: badge.color)
                    }
                }
            }
        }
    }

    private func badgeContent(label: String, icon: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption2)
            Text(label)
                .appFont(.caption)
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(color)
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(color.opacity(0.12), in: Capsule())
    }

    private static func computeBadges(state: BlueskyViewerState, blockingListNames: [String]) -> [(label: String, icon: String, color: Color)] {
        var badges: [(label: String, icon: String, color: Color)] = []
        if state.followsYou {
            badges.append((loc("profile.badge.follows_me"), "person.crop.circle.badge.checkmark", .green))
        }
        if state.blockedBy {
            badges.append((loc("profile.badge.blocks_me"), "hand.raised.slash.fill", .red))
        }
        if state.isFollowing {
            badges.append((loc("profile.badge.following"), "heart.fill", .blue))
        }
        if !blockingListNames.isEmpty {
            let count = blockingListNames.count
            let label = loc("profile.badge.blocking_by_my_lists").replacingOccurrences(of: "{n}", with: "\(count)")
            badges.append((label, "list.bullet", .orange))
        }
        if state.isBlocking {
            badges.append((loc("profile.badge.blocking"), "hand.raised.fill", .orange))
        }
        return badges
    }

    private static func formattedBlockingList(_ names: [String]) -> String {
        guard !names.isEmpty else { return "" }
        return loc("profile.block.by_list_notice").replacingOccurrences(of: "{list}", with: names.joined(separator: ", "))
    }

    private func statusChip(title: String, tint: Color, emphasized: Bool) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(emphasized ? tint : Color.secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background {
                if #available(iOS 26, *) {
                    Color.clear.glassEffect(.regular.tint(emphasized ? tint : Color.secondary), in: .rect(cornerRadius: .infinity))
                } else {
                    Color.clear.background((emphasized ? tint : Color.secondary).opacity(0.12), in: Capsule())
                }
            }
    }

    private func runModeration(_ operation: @escaping @Sendable () async -> Void) {
        moderationTask?.cancel()
        moderationTask = Task {
            await operation()
        }
    }

    private func runExport(_ format: ExportFileFormat, account: AppAccount, appPassword: String) {
        exportTask?.cancel()
        exportTask = Task {
            defer { isExportActive = false }
            if let url = await viewModel.exportPosts(as: format, account: account, appPassword: appPassword, using: container.blueskyClient) {
                try? await Task.sleep(for: .milliseconds(600))
                shareFileURL = url
                showExportSheet = false
            }
        }
    }

    private func runLoad(
        operation: @escaping @Sendable () async -> Void
    ) async {
        let task = startLoadTask(operation: operation)
        await task.value
    }

    @discardableResult
    private func startLoadTask(
        operation: @escaping @Sendable () async -> Void
    ) -> Task<Void, Never> {
        loadTask?.cancel()
        let task = Task {
            await operation()
        }
        loadTask = task
        return task
    }

    private func formatDateRelative(dateString: Date) -> String {
        let daysSince = Calendar.current.dateComponents([.day], from: dateString, to: Date()).day ?? 0
        if daysSince < 28 {
            let relativeFormatter = RelativeDateTimeFormatter()
            relativeFormatter.unitsStyle = .short
            relativeFormatter.locale = Locale(identifier: LocalizationManager.shared.currentLanguage)
            return relativeFormatter.localizedString(for: dateString, relativeTo: Date())
        }
        return dateString.formatted(date: .abbreviated, time: .omitted)
    }

    private func helpSheet(title: String, text: String) -> some View {
        NavigationStack {
            List {
                Section {
                    Text(text)
                        .font(.body)
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle(title)
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    ToolbarCloseButton()
                }
            }
        }
    }
}

private struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context _: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_: UIActivityViewController, context _: Context) {}
}

#Preview {
    NavigationStack {
        BlueskyProfileView(
            member: BlueskyListMember(
                recordURI: "at://did:plc:preview/app.bsky.graph.listitem/1",
                actor: BlueskyActor(did: "did:plc:1", handle: "alice.bsky.social", displayName: "Alice Chen")
            ),
            list: BlueskyList(
                id: "at://did:plc:preview/app.bsky.graph.list/123",
                name: "Trusted Sources",
                description: "Accounts curated for signal over noise.",
                memberCount: 67,
                kind: .regular
            )
        )
    }
    .environmentObject(AccountStore(preview: true))
    .environmentObject(PreviewBlueskyClient())
}
