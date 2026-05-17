import SwiftUI

struct ListsView: View {
    @EnvironmentObject private var accountStore: AccountStore
    @EnvironmentObject private var blueskyClient: LiveBlueskyClient
    @EnvironmentObject private var workspaceStore: ModerationWorkspaceStore
    @EnvironmentObject private var localizationManager: LocalizationManager
    @StateObject private var viewModel = ListsViewModel()
    @State private var presentationState = PresentationState()
    @State private var isShowingUserSearch = false
    @State private var exportFormat: ExportFormat?
    @State private var isShowingListPicker = false
    @State private var shareFileURL: URL?
    @State private var isExporting = false
    @State private var exportProgressMessage: String?
    @State private var exportProgressFraction: Double?
    @State private var showShareSheet = false

    var body: some View {
        NavigationStack {
            Group {
                if accountStore.accounts.isEmpty {
                    EmptyStatePanel(
                        title: localizationManager.localized("lists.no_account.title"),
                        message: localizationManager.localized("lists.no_account.desc")
                    )
                } else if viewModel.isLoading, !viewModel.isRefreshing, viewModel.listsByKind.isEmpty {
                    LoadingPanel(message: localizationManager.localized("lists.loading"))
                } else {
                    List {
                        if let activeAccount = accountStore.activeAccount {
                            Section {
                                Button {
                                    presentationState.showProfile = true
                                } label: {
                                    AccountSummaryCard(
                                        account: activeAccount,
                                        avatarURL: viewModel.activeProfile?.avatarURL
                                    )
                                }
                                .buttonStyle(.plain)
                                .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
                                .listRowBackground(Color.clear)
                            }
                        }

                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading) {
                            Button {
                                presentationState.showFollowers = true
                            } label: {
                                relationshipRow(
                                    label: loc("lists.followers"),
                                    count: viewModel.activeProfile?.followersCount ?? 0
                                )
                            }
                            .buttonStyle(.plain)

                            Button {
                                presentationState.showFollowing = true
                            } label: {
                                relationshipRow(
                                    label: loc("lists.following"),
                                    count: viewModel.activeProfile?.followsCount ?? 0
                                )
                            }
                            .buttonStyle(.plain)

                            Button {
                                presentationState.showBlocking = true
                            } label: {
                                relationshipRow(
                                    label: loc("lists.blocking"),
                                    count: viewModel.blockingCount
                                )
                            }
                            .buttonStyle(.plain)

                            Button {
                                presentationState.showBlockedBy = true
                            } label: {
                                relationshipRow(
                                    label: loc("lists.blocked_by"),
                                    count: viewModel.blockedByCount
                                )
                            }
                            .buttonStyle(.plain)
                        }
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                        .listSectionSeparator(.hidden)

                        Section {
                            if let lists = viewModel.listsByKind[.moderation], !lists.isEmpty {
                                ForEach(lists) { list in
                                    NavigationLink {
                                        ListDetailView(list: list) { updatedList in
                                            viewModel.updateList(updatedList)
                                        }
                                    } label: {
                                        ListRowView(list: list)
                                            .accessibilityLabel(loc("list.row.label").replacingOccurrences(of: "{name}", with: list.name).replacingOccurrences(of: "{count}", with: "\(list.memberCount ?? 0)"))
                                    }
                                    .buttonStyle(.plain)
                                }
                            } else {
                                Button {
                                    presentationState.createListKind = .moderation
                                    presentationState.isShowingCreateList = true
                                } label: {
                                    HStack(spacing: 12) {
                                        Image(systemName: "plus.circle.fill")
                                            .font(.title3)
                                            .foregroundStyle(.secondary)
                                        Text(loc("lists.create_first_mod"))
                                            .font(.subheadline)
                                            .foregroundStyle(.secondary)
                                        Spacer()
                                    }
                                    .padding(.vertical, 4)
                                }
                            }
                        } header: {
                            HStack {
                                Text(loc("lists.moderation_lists"))
                                Spacer()
                                Button {
                                    presentationState.createListKind = .moderation
                                    presentationState.isShowingCreateList = true
                                } label: {
                                    Image(systemName: "plus")
                                }
                            }
                        }

                        Section {
                            if let lists = viewModel.listsByKind[.regular], !lists.isEmpty {
                                ForEach(lists) { list in
                                    NavigationLink {
                                        ListDetailView(list: list) { updatedList in
                                            viewModel.updateList(updatedList)
                                        }
                                    } label: {
                                        ListRowView(list: list)
                                            .accessibilityLabel(loc("list.row.label").replacingOccurrences(of: "{name}", with: list.name).replacingOccurrences(of: "{count}", with: "\(list.memberCount ?? 0)"))
                                    }
                                    .buttonStyle(.plain)
                                }
                            } else {
                                Button {
                                    presentationState.createListKind = .regular
                                    presentationState.isShowingCreateList = true
                                } label: {
                                    HStack(spacing: 12) {
                                        Image(systemName: "plus.circle.fill")
                                            .font(.title3)
                                            .foregroundStyle(.secondary)
                                        Text(loc("lists.create_first"))
                                            .font(.subheadline)
                                            .foregroundStyle(.secondary)
                                        Spacer()
                                    }
                                    .padding(.vertical, 4)
                                }
                            }
                        } header: {
                            HStack {
                                Text(loc("lists.lists"))
                                Spacer()
                                Button {
                                    presentationState.createListKind = .regular
                                    presentationState.isShowingCreateList = true
                                } label: {
                                    Image(systemName: "plus")
                                }
                            }
                        }

                        Section {
                            Button {
                                presentationState.showMentionsSearch = true
                            } label: {
                                HStack {
                                    Image(systemName: "at")
                                    Text(loc("lists.advanced.mentions_button"))
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                                .padding(.vertical, 4)
                            }
                            Button {
                                presentationState.showCustomSearch = true
                            } label: {
                                HStack {
                                    Image(systemName: "magnifyingglass")
                                    Text(loc("lists.advanced.customsearch_button"))
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                                .padding(.vertical, 4)
                            }
                        } header: {
                            Text(loc("lists.advanced"))
                        }

                        if let errorMessage = viewModel.errorMessage {
                            ErrorRetryBanner(message: errorMessage) {
                                viewModel.errorMessage = nil
                                Task {
                                    await reload()
                                }
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                    .refreshable {
                        await reload()
                    }
                }
            }
            .navigationTitle("")
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        isShowingUserSearch = true
                    } label: {
                        Image(systemName: "magnifyingglass")
                    }
                    .disabled(accountStore.activeAccount == nil)
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await reload() }
                    } label: {
                        if viewModel.isRefreshing {
                            ProgressView()
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                    .accessibilityLabel(loc("lists.refresh.label"))
                    .disabled(accountStore.activeAccount == nil || viewModel.isRefreshing)
                }
            }
            .sheet(isPresented: $presentationState.isShowingAccountPicker) {
                AccountSwitcherSheet(isPresented: $presentationState.isShowingAccountPicker)
                    .environmentObject(accountStore)
            }

            .sheet(isPresented: $presentationState.isShowingBulkLookup) {
                NavigationStack {
                    BulkProfileLookupView()
                        .environmentObject(accountStore)
                        .environmentObject(blueskyClient)
                }
            }
            .sheet(isPresented: $presentationState.isShowingCreateList) {
                ListMetadataSheet(mode: .create(kind: presentationState.createListKind)) { name, description, kind in
                    if let account = accountStore.activeAccount,
                       let appPassword = accountStore.appPassword(for: account)
                    {
                        Task {
                            do {
                                let newList = try await blueskyClient.createList(
                                    name: name,
                                    description: description,
                                    kind: kind,
                                    account: account,
                                    appPassword: appPassword
                                )
                                viewModel.addList(newList)
                            } catch {
                                viewModel.errorMessage = AppError.userMessage(from: error)
                            }
                        }
                    }
                }
                .environmentObject(accountStore)
                .environmentObject(blueskyClient)
            }
            .sheet(isPresented: $isShowingUserSearch) {
                NavigationStack {
                    UserSearchSheet()
                        .environmentObject(accountStore)
                        .environmentObject(blueskyClient)
                }
            }
            .sheet(isPresented: $isShowingListPicker) {
                exportListPickerSheet
            }
            .sheet(isPresented: $presentationState.isShowingAccountManagement) {
                NavigationStack {
                    AccountSwitcherSheet(isPresented: $presentationState.isShowingAccountManagement)
                        .environmentObject(accountStore)
                        .environmentObject(blueskyClient)
                }
            }
            .task(id: accountStore.activeAccountID) {
                await loadInitial()
            }
            .onChange(of: accountStore.activeAccountID) { _, newValue in
                viewModel.reset()
                if newValue != nil {
                    Task { await loadInitial() }
                }
            }
            .navigationDestination(isPresented: $presentationState.showProfile) {
                if let activeAccount = accountStore.activeAccount {
                    BlueskyProfileView(
                        member: activeAccountMember(activeAccount),
                        list: nil
                    )
                    .environmentObject(accountStore)
                    .environmentObject(blueskyClient)
                }
            }
            .navigationDestination(isPresented: $presentationState.showFollowers) {
                RelationshipsView(mode: .followers, initialCount: viewModel.activeProfile?.followersCount)
                    .environmentObject(accountStore)
                    .environmentObject(blueskyClient)
            }
            .navigationDestination(isPresented: $presentationState.showFollowing) {
                RelationshipsView(mode: .following, initialCount: viewModel.activeProfile?.followsCount)
                    .environmentObject(accountStore)
                    .environmentObject(blueskyClient)
            }
            .navigationDestination(isPresented: $presentationState.showBlocking) {
                RelationshipsView(mode: .blocking, initialCount: viewModel.blockingCount)
                    .environmentObject(accountStore)
                    .environmentObject(blueskyClient)
            }
            .navigationDestination(isPresented: $presentationState.showBlockedBy) {
                RelationshipsView(mode: .blockedBy, initialCount: viewModel.blockedByCount)
                    .environmentObject(accountStore)
                    .environmentObject(blueskyClient)
            }
            .navigationDestination(isPresented: $presentationState.showMentionsSearch) {
                if let activeAccount = accountStore.activeAccount {
                    MentionsSearchView(
                        did: activeAccount.did ?? activeAccount.handle,
                        handle: activeAccount.handle,
                        displayName: activeAccount.displayName ?? activeAccount.handle
                    )
                    .environmentObject(accountStore)
                    .environmentObject(blueskyClient)
                }
            }
            .navigationDestination(isPresented: $presentationState.showCustomSearch) {
                CustomSearchView()
                    .environmentObject(accountStore)
                    .environmentObject(blueskyClient)
            }
        }
        .id(workspaceStore.moderationNavigationResetToken)
        .onChange(of: workspaceStore.moderationNavigationResetToken) { _, _ in
            presentationState = PresentationState()
            exportFormat = nil
            isShowingListPicker = false
            shareFileURL = nil
            isExporting = false
            exportProgressMessage = nil
            exportProgressFraction = nil
            showShareSheet = false
        }
    }

    private func loadInitial() async {
        let password = accountStore.activeAccount.flatMap { accountStore.appPassword(for: $0) }
        await viewModel.load(
            for: accountStore.activeAccount,
            appPassword: password,
            using: blueskyClient
        )
    }

    private func reload() async {
        let password = accountStore.activeAccount.flatMap { accountStore.appPassword(for: $0) }
        await viewModel.load(
            for: accountStore.activeAccount,
            appPassword: password,
            using: blueskyClient,
            isExplicitRefresh: true
        )
    }

    private func relationshipRow(label: String, count: Int) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text(label)
                    .appFont(.heading)
                    .lineLimit(1)
                    .foregroundStyle(.primary)
                Text("\(count)")
                    .appFont(.statistic)
                    .foregroundStyle(Color.skyPrimary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .appFont(.subheading)
                .foregroundStyle(Color.skyPrimary.opacity(0.8))
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(LinearGradient.cardSurfaceGradient)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.skyPrimary.opacity(0.12), lineWidth: 1)
        }
        .appButtonAccessibility(label: label, hint: loc("rel.view.hint"))
    }

    private func activeAccountMember(_ account: AppAccount) -> BlueskyListMember {
        BlueskyListMember(
            recordURI: "account:\(account.id.uuidString)",
            actor: BlueskyActor(
                did: account.did ?? account.handle,
                handle: account.handle,
                displayName: account.displayName,
                avatarURL: viewModel.activeProfile?.avatarURL
            )
        )
    }

    private func openAccountManagement() {
        presentationState.isShowingAccountManagement = true
    }

    private var exportListPickerSheet: some View {
        NavigationStack {
            let lists = allListsWithMembers
            List {
                if lists.isEmpty {
                    ContentUnavailableView(
                        loc("lists.export.no_members"),
                        systemImage: "arrow.down.doc",
                        description: Text(verbatim: loc("lists.export.no_members_desc"))
                    )
                }
                ForEach(lists) { list in
                    Button {
                        Task { await performExport(list: list) }
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(list.name)
                                    .font(.body.weight(.semibold))
                                    .foregroundStyle(.primary)
                                if let count = list.memberCount {
                                    Text("\(count) members")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            if isExporting {
                                ProgressView()
                            } else {
                                Image(systemName: "arrow.down.doc")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .disabled(isExporting)
                }

                if let msg = exportProgressMessage {
                    HStack(spacing: 8) {
                        if let fraction = exportProgressFraction {
                            ProgressView(value: fraction)
                                .frame(width: 60)
                        } else {
                            ProgressView()
                                .scaleEffect(0.8)
                        }
                        Text(msg)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 8)
                }
            }
            .navigationTitle(loc("lists.export.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(loc("actions.cancel")) { isShowingListPicker = false }
                        .disabled(isExporting)
                }
            }
            .sheet(isPresented: $showShareSheet, onDismiss: {
                isShowingListPicker = false
                isExporting = false
                shareFileURL = nil
                exportProgressMessage = nil
                exportProgressFraction = nil
            }) {
                if let url = shareFileURL {
                    ShareSheet(activityItems: [url])
                }
            }
            .onChange(of: shareFileURL) { _, url in
                if url != nil { showShareSheet = true }
            }
        }
    }

    private var allListsWithMembers: [BlueskyList] {
        viewModel.listsByKind.values
            .flatMap(\.self)
            .filter { ($0.memberCount ?? 0) > 0 }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func performExport(list: BlueskyList) async {
        guard let account = accountStore.activeAccount,
              let appPassword = accountStore.appPassword(for: account),
              let format = exportFormat else { return }

        isExporting = true

        exportProgressMessage = "Processing..."
        let members: [BlueskyListMember]
        do {
            members = try await blueskyClient.fetchListMembers(list: list, account: account, appPassword: appPassword)
        } catch {
            isExporting = false
            exportProgressMessage = nil
            viewModel.errorMessage = AppError.userMessage(from: error)
            return
        }

        guard !members.isEmpty else {
            isExporting = false
            exportProgressMessage = nil
            return
        }

        let dids = members.map(\.actor.did)
        _ = (dids.count + 24) / 25
        exportProgressFraction = 0
        let stats = await (try? LiveBlueskyClient.fetchProfileStats(dids: dids) { current, total in
            Task { @MainActor in
                exportProgressFraction = Double(current) / Double(total)
                exportProgressMessage = "Processing... \(current)/\(total)"
            }
        }) ?? [:]

        exportProgressMessage = "Processing..."

        let sanitizedName = list.name.lowercased().replacingOccurrences(of: " ", with: "-")
        let fileName = "\(sanitizedName)-full-export.\(format.rawValue)"
        let data: Data

        switch format {
        case .csv:
            let csv = generateCSV(from: members, stats: stats)
            data = Data(csv.utf8)
        case .json:
            data = generateJSON(from: members, stats: stats)
        case .xlsx, .ods:
            let headers = ["handle", "did", "display_name", "followers", "following", "posts", "description"]
            let rows = members.map { member in
                let s = stats[member.actor.did]
                return [
                    member.actor.handle,
                    member.actor.did,
                    member.actor.displayName ?? "",
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

        let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        try? data.write(to: url, options: .atomic)
        exportProgressFraction = nil
        exportProgressMessage = "Done"
        shareFileURL = url
    }

    private func generateCSV(from members: [BlueskyListMember], stats: [String: (followers: Int, following: Int, posts: Int, description: String)] = [:]) -> String {
        let header = "handle,did,display_name,followers,following,posts,description"
        let rows = members.map { member in
            let s = stats[member.actor.did]
            return [
                member.actor.handle.csvField,
                member.actor.did.csvField,
                (member.actor.displayName ?? "").csvField,
                "\(s?.followers ?? 0)",
                "\(s?.following ?? 0)",
                "\(s?.posts ?? 0)",
                (s?.description ?? "").csvField,
            ].joined(separator: ",")
        }
        return ([header] + rows).joined(separator: "\n")
    }

    private func generateJSON(from members: [BlueskyListMember], stats: [String: (followers: Int, following: Int, posts: Int, description: String)] = [:]) -> Data {
        let objects = members.map { member in
            let s = stats[member.actor.did]
            return [
                "handle": member.actor.handle,
                "did": member.actor.did,
                "display_name": member.actor.displayName ?? "",
                "description": s?.description ?? "",
                "followers": s?.followers ?? 0,
                "following": s?.following ?? 0,
                "posts": s?.posts ?? 0,
            ] as [String: Any]
        }
        return (try? JSONSerialization.data(withJSONObject: objects, options: [.prettyPrinted, .sortedKeys])) ?? Data()
    }
}

private enum ExportFormat: String, CaseIterable {
    case csv, json, xlsx, ods
}

private struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context _: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_: UIActivityViewController, context _: Context) {}
}

#Preview {
    ListsView()
        .environmentObject(AccountStore(preview: true))
        .environmentObject(PreviewBlueskyClient())
}
