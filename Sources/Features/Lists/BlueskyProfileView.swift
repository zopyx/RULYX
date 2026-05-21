import SwiftUI

struct BlueskyProfileView: View {
    let member: BlueskyListMember
    let list: BlueskyList?

    @EnvironmentObject private var accountStore: AccountStore
    @EnvironmentObject private var blueskyClient: LiveBlueskyClient
    @EnvironmentObject private var workspaceStore: ModerationWorkspaceStore
    @EnvironmentObject private var chatStore: ChatStore
    @EnvironmentObject private var localizationManager: LocalizationManager
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = BlueskyProfileViewModel()
    @AppStorage("showBetaFeatures") private var showBetaFeatures = false
    @State private var isShowingAvatarPreview = false
    @State private var showPostBrowser = false
    @State private var showMediaBrowser = false
    @State private var shareFileURL: URL?
    @State private var loadTask: Task<Void, Never>?
    @State private var moderationTask: Task<Void, Never>?
    @State private var exportTask: Task<Void, Never>?
    @State private var blockedAccessType: BlockedAccessType?
    @State private var blockingCount: Int?
    @State private var blockedByCount: Int?
    @State private var isFetchingBlockCounts = false
    @State private var isBlockingBack = false
    @State private var blockBackCompleted = 0
    @State private var blockBackTotal = 0
    @State private var blockBackSuccessCount = 0
    @State private var blockBackFailureCount = 0
    @State private var blockBackError: String?
    @State private var showBlockBackResult = false
    @State private var showBlockBackConfirm1 = false
    @State private var showBlockBackConfirm2 = false
    @State private var showClearskyLists = false
    @State private var showOwnedLists = false
    @State private var reportReasonText = ""
    @State private var unblockedBlockersCount: Int?
    @State private var searchAccount: AppAccount?
    @State private var showCreateModerationList = false
    @State private var showCreateRegularList = false
    @State private var showModerationListsHelp = false
    @State private var showListsHelp = false

    private var preferredSearchAccount: AppAccount? {
        if let prefID = accountStore.preferredSearchAccountID,
           let prefAccount = accountStore.accounts.first(where: { $0.id == prefID })
        {
            prefAccount
        } else {
            accountStore.activeAccount
        }
    }

    enum BlockedAccessType: String, Identifiable {
        case posts
        case media
        var id: String {
            rawValue
        }
    }

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
        .navigationTitle("")
        .toolbarTitleDisplayMode(.inline)
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
                UserPostsView(did: profile.did, displayName: profile.displayName ?? profile.handle)
                    .environmentObject(accountStore)
                    .environmentObject(blueskyClient)
            }
        }
        .sheet(item: $shareFileURL) { url in
            ShareSheet(activityItems: [url])
        }
        .sheet(isPresented: $showMediaBrowser) {
            if let profile = viewModel.profile {
                MediaBrowserView(did: profile.did, handle: profile.handle)
                    .environmentObject(accountStore)
                    .environmentObject(blueskyClient)
            }
        }
        .sheet(isPresented: $showClearskyLists) {
            ClearskyListsView(entries: viewModel.clearskyLists)
                .environmentObject(accountStore)
                .environmentObject(blueskyClient)
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
                                    .environmentObject(blueskyClient)
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
                                using: blueskyClient
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
                        Text("profile.blocked.\(type.rawValue)_desc")
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.horizontal, 32)

                    Spacer()
                }
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("actions.got_it") { blockedAccessType = nil }
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
                            using: blueskyClient
                        )
                    }
                }
                .environmentObject(accountStore)
                .environmentObject(blueskyClient)
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
                            using: blueskyClient
                        )
                    }
                }
                .environmentObject(accountStore)
                .environmentObject(blueskyClient)
            }
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
    }

    // swiftlint:disable:next function_body_length cyclomatic_complexity
    private func content(account: AppAccount, appPassword: String) -> some View {
        List {
            if let profile = viewModel.profile {
                Section {
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
                            relationshipBadges(state: state)
                        }
                    }
                    .padding(.vertical, 6)
                }

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
                        if profile.viewerState?.blockedBy == true {
                            blockedAccessType = .posts
                        } else {
                            showPostBrowser = true
                        }
                    } label: {
                        HStack {
                            Text(loc: "profile.stats.posts")
                            Spacer()
                            Text(statText(profile.postsCount))
                                .foregroundStyle(.secondary)
                            Image(systemName: "chevron.right")
                                .flipsForRightToLeftLayoutDirection(true)
                                .appFont(.subheading)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .buttonStyle(.plain)
                    Button {
                        if profile.viewerState?.blockedBy == true {
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
                                    .foregroundStyle(.tertiary)
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
                                    .foregroundStyle(.tertiary)
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
                                    .foregroundStyle(.tertiary)
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
                    Text(loc: "profile.stats")
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
                                            using: blueskyClient
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
                                            using: blueskyClient
                                        )
                                    }
                                }
                            )) {
                                Label { Text(loc: "profile.block") } icon: { Image(systemName: "hand.raised") }
                            }
                            .disabled(viewModel.isUpdatingModeration)
                            .accessibilityHint(viewerState.isBlocking ? loc("profile.unblock.hint") : loc("profile.block.hint"))

                            Toggle(isOn: Binding(
                                get: { viewModel.pendingMuteState ?? viewerState.muted },
                                set: { _ in
                                    runModeration {
                                        await viewModel.toggleMute(
                                            account: account,
                                            appPassword: appPassword,
                                            using: blueskyClient
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
                                Toggle(isOn: Binding(
                                    get: { viewModel.pendingListMemberStates[membership.listURI] ?? membership.isMember },
                                    set: { _ in
                                        runModeration {
                                            await viewModel.toggleListMembership(
                                                membership,
                                                account: account,
                                                appPassword: appPassword,
                                                using: blueskyClient
                                            )
                                        }
                                    }
                                )) {
                                    Text(membership.name)
                                }
                                .disabled(viewModel.isUpdatingListMembership)
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
                                showCreateModerationList = true
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
                                Toggle(isOn: Binding(
                                    get: { viewModel.pendingListMemberStates[membership.listURI] ?? membership.isMember },
                                    set: { _ in
                                        runModeration {
                                            await viewModel.toggleListMembership(
                                                membership,
                                                account: account,
                                                appPassword: appPassword,
                                                using: blueskyClient
                                            )
                                        }
                                    }
                                )) {
                                    Text(membership.name)
                                }
                                .disabled(viewModel.isUpdatingListMembership)
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
                                showCreateRegularList = true
                            } label: {
                                Image(systemName: "plus")
                                    .font(.subheadline.weight(.semibold))
                                    .accessibilityLabel(loc("profile.create_regular_list"))
                            }
                            .disabled(viewModel.isCreatingList)
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
                                viewModel.statusMessage = "Handle copied"
                            } label: {
                                Image(systemName: "doc.on.doc")
                                    .font(.caption)
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.tertiary)
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
                                viewModel.statusMessage = "DID copied"
                            } label: {
                                Image(systemName: "doc.on.doc")
                                    .font(.caption)
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.tertiary)
                        }
                    } label: {
                        Text(loc: "profile.stats.did")
                    }
                    if let createdAt = profile.createdAt {
                        LabeledContent("profile.stats.joined", value: createdAt.formatted(date: .abbreviated, time: .omitted))
                    }
                    if !profile.labels.isEmpty {
                        LabeledContent("profile.stats.labels", value: profile.labels.joined(separator: ", "))
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
                                    .foregroundStyle(.tertiary)
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
                            Label { Text(loc: "profile.report") } icon: { Image(systemName: "exclamationmark.shield") }
                        }
                        .disabled(viewModel.isReporting)
                        .accessibilityHint(loc("profile.report.hint"))

                        if let list {
                            Label { Text(verbatim: loc("profile.member_of").replacingOccurrences(of: "{list}", with: list.name)) } icon: { Image(systemName: "person.2.badge.gearshape") }
                                .foregroundStyle(.secondary)
                        }

                        if showBetaFeatures {
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
                        }

                    } header: {
                        Text(loc: "profile.actions_section")
                    }
                }

                if isOwnProfile, showBetaFeatures {
                    Section {
                        if isFetchingBlockCounts {
                            HStack {
                                ProgressView()
                                    .scaleEffect(0.7)
                                Text(loc: "profile.block_back.loading")
                                    .foregroundStyle(.secondary)
                            }
                        } else {
                            LabeledContent("profile.block_back.blocking", value: countText(blockingCount))
                            LabeledContent("profile.block_back.blocked_by", value: countText(blockedByCount))

                            if isBlockingBack, blockBackTotal > 0 {
                                VStack(spacing: 6) {
                                    ProgressView(value: Double(blockBackCompleted), total: Double(blockBackTotal))
                                        .progressViewStyle(.linear)
                                        .tint(Color.skyPrimary)
                                    HStack {
                                        Text(loc("profile.block_back.progress")
                                            .replacingOccurrences(of: "{completed}", with: "\(blockBackCompleted)")
                                            .replacingOccurrences(of: "{total}", with: "\(blockBackTotal)"))
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                        Spacer()
                                    }
                                }
                                .padding(.vertical, 4)
                            } else if showBlockBackResult {
                                HStack(spacing: 8) {
                                    if blockBackFailureCount == 0 {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(.green)
                                    } else {
                                        Image(systemName: "exclamationmark.triangle.fill")
                                            .foregroundStyle(.orange)
                                    }
                                    Text(blockBackResultSummary)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                                .padding(.vertical, 4)
                            } else if let count = unblockedBlockersCount, count > 0 {
                                Button {
                                    showBlockBackConfirm1 = true
                                } label: {
                                    HStack {
                                        Label("profile.block_back.action", systemImage: "hand.raised.slash.fill")
                                        Spacer()
                                        Text("\(count)")
                                            .foregroundStyle(.secondary)
                                            .font(.caption.weight(.semibold))
                                        Image(systemName: "chevron.right")
                                            .flipsForRightToLeftLayoutDirection(true)
                                            .appFont(.subheading)
                                            .foregroundStyle(.tertiary)
                                    }
                                }
                            } else if let blockedBy = blockedByCount {
                                if blockedBy == 0 {
                                    Label("profile.block_back.none_blocking", systemImage: "checkmark.circle.fill")
                                        .foregroundStyle(.green)
                                } else {
                                    Label("profile.block_back.all_clear", systemImage: "checkmark.circle.fill")
                                        .foregroundStyle(.green)
                                }
                            }
                        }

                        if let error = blockBackError {
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
                            appPassword: appPassword,
                            using: blueskyClient
                        )
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .refreshable {
            await runLoad {
                await viewModel.load(
                    did: member.actor.did,
                    account: account,
                    appPassword: appPassword,
                    using: blueskyClient
                )
            }
        }
        .task {
            await runLoad {
                await viewModel.loadIfNeeded(
                    did: member.actor.did,
                    account: account,
                    appPassword: appPassword,
                    using: blueskyClient
                )
            }
        }
        .onDisappear {
            loadTask?.cancel()
            moderationTask?.cancel()
            exportTask?.cancel()
        }
        .task(id: viewModel.profile?.did) {
            searchAccount = preferredSearchAccount
            async let blocks = fetchBlockCounts()
            if let handle = viewModel.profile?.handle, let did = viewModel.profile?.did {
                async let lists = viewModel.fetchClearskyLists(handle: handle, using: blueskyClient)
                if let acct = searchAccount, let password = accountStore.appPassword(for: acct) {
                    async let owned = viewModel.fetchOwnedLists(did: did, account: acct, appPassword: password, using: blueskyClient)

                    _ = await (blocks, lists, owned)
                } else {
                    _ = await (blocks, lists)
                }
            } else {
                await blocks
            }
        }
        .alert(Text(loc: "profile.block_back.confirm.first.title"), isPresented: $showBlockBackConfirm1) {
            Button(loc("actions.cancel"), role: .cancel) {}
            Button("profile.block_back.action") {
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
                Task {
                    await blockBack(account: account, appPassword: appPassword)
                }
            }
        } message: {
            if let count = unblockedBlockersCount {
                Text(loc("profile.block_back.confirm.second.message").replacingOccurrences(of: "{count}", with: "\(count)"))
            }
        }
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
        if let activeDID = activeAccount.did, activeDID == profile.did { return true }
        return activeAccount.handle.lowercased() == profile.handle.lowercased()
    }

    private var blockBackResultSummary: String {
        if blockBackFailureCount == 0 {
            return loc("profile.block_back.result_success")
                .replacingOccurrences(of: "{count}", with: "\(blockBackSuccessCount)")
        }
        return loc("profile.block_back.result")
            .replacingOccurrences(of: "{success}", with: "\(blockBackSuccessCount)")
            .replacingOccurrences(of: "{fail}", with: "\(blockBackFailureCount)")
    }

    private func countText(_ value: Int?) -> String {
        if let value { return "\(value)" }
        return "-"
    }

    private func fetchBlockCounts() async {
        guard let account = accountStore.activeAccount,
              accountStore.appPassword(for: account) != nil else { return }
        guard isOwnProfile, showBetaFeatures else { return }
        isFetchingBlockCounts = true
        do {
            async let b = blueskyClient.fetchBlockedByCount(for: account)
            async let k = blueskyClient.fetchBlockingCount(for: account)
            async let u = blueskyClient.fetchUnblockedBlockersCount(for: account)
            (blockedByCount, blockingCount, unblockedBlockersCount) = try await (b, k, u)
        } catch {
            AppLogger.moderation.error("Failed to fetch block counts: \(error.localizedDescription, privacy: .public)")
        }
        isFetchingBlockCounts = false
    }

    private func blockBack(account: AppAccount, appPassword: String) async {
        isBlockingBack = true
        blockBackError = nil
        blockBackCompleted = 0
        blockBackTotal = 0
        blockBackSuccessCount = 0
        blockBackFailureCount = 0
        showBlockBackResult = false

        do {
            async let blockedByResult = blueskyClient.fetchBlockedByActors(account: account, appPassword: appPassword)
            async let blockedResult = blueskyClient.fetchBlockedActors(account: account, appPassword: appPassword)
            let (blockedByActors, blockedActors) = try await (blockedByResult.actors, blockedResult.actors)

            let blockedDIDs = Set(blockedActors.map(\.did))
            let toBlock = blockedByActors.filter { !blockedDIDs.contains($0.did) }

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
                                AppLogger.moderation.error("Block back failed for \(actor.handle, privacy: .public): \(error.localizedDescription, privacy: .public)")
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

            showBlockBackResult = true
            await fetchBlockCounts()

            try? await Task.sleep(for: .seconds(4))
            showBlockBackResult = false
        } catch {
            if blockBackSuccessCount == 0, blockBackFailureCount == 0 {
                blockBackError = error.localizedDescription
            } else {
                showBlockBackResult = true
                try? await Task.sleep(for: .seconds(4))
                showBlockBackResult = false
            }
        }

        isBlockingBack = false
    }

    @ViewBuilder
    private func relationshipBadges(state: BlueskyViewerState) -> some View {
        let badges: [(label: String, icon: String, color: Color, active: Bool)] = [
            (loc("profile.badge.follows_me"), "person.crop.circle.badge.checkmark", .green, state.followsYou),
            (loc("profile.badge.blocks_me"), "hand.raised.slash.fill", .red, state.blockedBy),
            (loc("profile.badge.following"), "heart.fill", .blue, state.isFollowing),
            (loc("profile.badge.blocking"), "hand.raised.fill", .orange, state.isBlocking),
        ]
        let active = badges.filter(\.active)
        if !active.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(active, id: \.label) { badge in
                        HStack(spacing: 4) {
                            Image(systemName: badge.icon)
                                .font(.caption2)
                            Text(badge.label)
                                .appFont(.caption)
                        }
                        .foregroundStyle(badge.color)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(badge.color.opacity(0.12), in: Capsule())
                    }
                }
            }
        }
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
            if let url = await viewModel.exportPosts(as: format, account: account, appPassword: appPassword, using: blueskyClient) {
                shareFileURL = url
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
