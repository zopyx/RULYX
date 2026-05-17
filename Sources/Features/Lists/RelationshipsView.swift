import SwiftUI

enum RelationshipMode: String, CaseIterable {
    case followers
    case following
    case blocking
    case blockedBy

    var title: String {
        switch self {
        case .followers: "My followers"
        case .following: "My followings"
        case .blocking: "Blocking"
        case .blockedBy: "Blocked by"
        }
    }

    func titled(_ count: Int) -> String {
        "\(title) (\(count))"
    }
}

struct RelationshipsView: View {
    let mode: RelationshipMode
    let initialCount: Int?
    var profileDID: String?
    var profileHandle: String?
    @EnvironmentObject private var accountStore: AccountStore
    @EnvironmentObject private var blueskyClient: LiveBlueskyClient
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

    private var filteredActors: [BlueskyActor] {
        let trimmed = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return actors }
        return actors.filter {
            $0.handle.lowercased().contains(trimmed) ||
                ($0.displayName?.lowercased().contains(trimmed) ?? false)
        }
    }

    private var modeLocalized: String {
        if let handle = profileHandle {
            switch mode {
            case .followers: return loc("rel.mode.followers_of").replacingOccurrences(of: "{handle}", with: handle)
            case .following: return loc("rel.mode.following_of").replacingOccurrences(of: "{handle}", with: handle)
            case .blocking: return loc("rel.mode.blocking")
            case .blockedBy: return loc("rel.mode.blocked_by")
            }
        }
        switch mode {
        case .followers: return loc("rel.mode.followers")
        case .following: return loc("rel.mode.following")
        case .blocking: return loc("rel.mode.blocking")
        case .blockedBy: return loc("rel.mode.blocked_by")
        }
    }

    var body: some View {
        Group {
            if isLoading {
                ProgressView(loc("rel.loading").replacingOccurrences(of: "{mode}", with: modeLocalized.lowercased()))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let errorMessage {
                ErrorRetryBanner(message: errorMessage) {
                    Task { await load() }
                }
            } else {
                List {
                    Section {
                        Text("\(modeLocalized) (\(clearskyTotal ?? actors.count))")
                            .font(.title2.weight(.bold))
                    }

                    if !actors.isEmpty {
                        Section {
                            TextField(loc("rel.search_placeholder").replacingOccurrences(of: "{mode}", with: modeLocalized.lowercased()), text: $searchQuery)
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
                            Text(searchQuery.isEmpty ? loc("rel.no_accounts") : loc("rel.no_matches"))
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
                                            Text(loc("rel.new_badge"))
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
                                .accessibilityHint(loc("rel.block.hint"))

                                Button {
                                    selectedActorForList = actor
                                    isShowingListPicker = true
                                } label: {
                                    Label(loc("rel.add_to_list"), systemImage: "list.bullet")
                                }
                                .accessibilityHint(loc("rel.add_to_list.hint"))
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button(role: .destructive) {
                                    actorToBlock = actor
                                    isShowingBlockConfirm = true
                                } label: {
                                    Label(loc("rel.block"), systemImage: "hand.raised.fill")
                                }
                                .accessibilityHint(loc("rel.block_swipe.hint"))
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
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 16) {
                    if !actors.isEmpty {
                        Menu {
                            Button {
                                isExporting = true
                                Task { await exportAll(format: .csv) }
                            } label: {
                                Label { Text(verbatim: loc("list.search.export_csv_all")) } icon: { Image(systemName: "arrow.down.doc") }
                            }

                            Button {
                                isExporting = true
                                Task { await exportAll(format: .json) }
                            } label: {
                                Label { Text(verbatim: loc("list.search.export_json_all")) } icon: { Image(systemName: "arrow.down.doc") }
                            }

                            Button {
                                isExporting = true
                                Task { await exportAll(format: .xlsx) }
                            } label: {
                                Label { Text(verbatim: loc("list.export.excel")) } icon: { Image(systemName: "arrow.down.doc") }
                            }

                            Button {
                                isExporting = true
                                Task { await exportAll(format: .ods) }
                            } label: {
                                Label { Text(verbatim: loc("list.export.ods")) } icon: { Image(systemName: "arrow.down.doc") }
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

                    if isLoading, actors.isEmpty {
                        ProgressView()
                    } else if isRefreshing {
                        ProgressView()
                    } else {
                        Button {
                            Task { await refresh() }
                        } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                        .accessibilityHint(loc("rel.refresh.hint"))
                        .disabled(isExporting)
                    }
                }
            }
        }
        .task {
            await load()
        }
        .confirmationDialog(
            loc("rel.block_confirm"),
            isPresented: $isShowingBlockConfirm,
            titleVisibility: .visible
        ) {
            Button(loc("rel.block"), role: .destructive) {
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
            Button(loc("actions.cancel"), role: .cancel) {}
                .accessibilityInputLabels([loc("actions.cancel")])

            Text(loc("rel.block_message"))
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
    }

    private func blockedDateDisplay(_ date: Date) -> String {
        let days = Calendar.current.dateComponents([.day], from: date, to: .now).day ?? 0
        if days < 30 {
            return date.formatted(.relative(presentation: .named))
        }
        return date.formatted(date: .abbreviated, time: .omitted)
    }

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

    private var cacheKey: String? {
        guard let accountDID = accountStore.activeAccount?.did else { return nil }
        let subject = profileDID ?? accountDID
        return "\(mode.rawValue)_\(subject)"
    }

    private func load() async {
        guard let account = accountStore.activeAccount,
              let appPassword = accountStore.appPassword(for: account)
        else {
            errorMessage = loc("rel.select_account_first")
            isLoading = false
            return
        }

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

    private func refresh() async {
        guard let account = accountStore.activeAccount,
              let appPassword = accountStore.appPassword(for: account) else { return }
        isRefreshing = true
        await fetchFromAPI(account: account, appPassword: appPassword)
        isRefreshing = false
    }

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
                statusMessage = loc("rel.loaded_status").replacingOccurrences(of: "{count}", with: "\(actors.count)").replacingOccurrences(of: "{total}", with: "\(initialCount ?? actors.count)")
            }
        }
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
                    ContentUnavailableView(loc("rel.no_lists_title"), systemImage: "tray", description: Text(loc("rel.no_lists_desc")))
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
                        .accessibilityHint(loc("rel.added_to_list.hint"))
                    }
                }
            }
            .navigationTitle("\(loc("rel.add_to_list")) \(actor.handle)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(loc("actions.cancel")) { dismiss() }
                        .accessibilityHint(loc("rel.close_picker.hint"))
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
