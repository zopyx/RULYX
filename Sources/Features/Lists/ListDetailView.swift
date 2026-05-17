import SwiftUI
import UniformTypeIdentifiers

struct ListDetailView: View {
    let onListUpdated: ((BlueskyList) -> Void)?

    @EnvironmentObject var accountStore: AccountStore
    @EnvironmentObject var blueskyClient: LiveBlueskyClient
    @EnvironmentObject var workspaceStore: ModerationWorkspaceStore
    @StateObject var viewModel = ListDetailViewModel()
    @StateObject var batchState = ListBatchProgressState()
    @State var currentList: BlueskyList
    @State var searchQuery = ""
    @State var memberSearchQuery = ""
    @State var importState = ImportState()
    @State var comparisonState = ComparisonState()
    @State var exportState = ExportState()
    @State private var isShowingDeleteConfirmation = false
    @State private var shareFileURL: URL?
    @State private var imagePreview: ImagePreviewCollection?
    @State private var isExporting = false
    @State private var exportProgressMessage: String?
    @State private var exportProgressFraction: Double?
    @State private var ownerActor: BlueskyActor?
    @Environment(\.dismiss) private var dismiss

    private var ownerDID: String? {
        let parts = currentList.id.split(separator: "/")
        guard parts.count >= 2, parts[0].description == "at:" else { return nil }
        return parts[1].description
    }

    private var isOwnedList: Bool {
        guard let activeDID = accountStore.activeAccount?.did else { return false }
        return currentList.id.hasPrefix("at://\(activeDID)")
    }

    init(list: BlueskyList, onListUpdated: ((BlueskyList) -> Void)? = nil) {
        self.onListUpdated = onListUpdated
        _currentList = State(initialValue: list)
    }

    var body: some View {
        rootContent
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(content: toolbarContent)
            .sheet(isPresented: $importState.isShowingEditSheet) {
                if let account = accountStore.activeAccount,
                   let appPassword = accountStore.appPassword(for: account)
                {
                    ListMetadataSheet(
                        mode: .edit(list: currentList, isSaving: viewModel.isUpdatingMetadata)
                    ) { title, description, _ in
                        Task {
                            if let updatedList = await viewModel.updateMetadata(
                                for: currentList,
                                title: title,
                                description: description,
                                account: account,
                                appPassword: appPassword,
                                using: blueskyClient
                            ) {
                                currentList = updatedList
                                onListUpdated?(updatedList)
                                importState.isShowingEditSheet = false
                            }
                        }
                    }
                }
            }
            .sheet(isPresented: $importState.isShowingImportSheet, content: importSheetContent)
            .sheet(isPresented: importPreviewPresentedBinding, content: importPreviewSheetContent)
            .fileImporter(
                isPresented: $importState.isShowingImportFilePicker,
                allowedContentTypes: [.plainText, .commaSeparatedText]
            ) { result in
                handleImportedFile(result)
            }
            .fullScreenCover(item: $imagePreview) { preview in
                ImageCarouselView(urls: preview.urls, initialIndex: preview.initialIndex) {
                    imagePreview = nil
                }
            }
            .sheet(isPresented: .init(get: { shareFileURL != nil }, set: { if !$0 { shareFileURL = nil } })) {
                if let url = shareFileURL {
                    ShareSheet(activityItems: [url])
                }
            }
            .alert(loc("list.detail.alert_title"), isPresented: .constant(viewModel.errorMessage != nil), actions: {
                Button(loc("actions.ok")) {
                    viewModel.errorMessage = nil
                }
                .accessibilityHint(loc("list.detail.dismiss_error.hint"))
                .accessibilityInputLabels([loc("actions.ok")])
            }, message: {
                Text(viewModel.errorMessage ?? "")
            })
            .alert(
                viewModel.bulkActionResult?.operation.title ?? loc("list.detail.bulk_update"),
                isPresented: bulkResultPresentedBinding
            ) {
                Button(loc("actions.ok")) {
                    viewModel.bulkActionResult = nil
                }
                .accessibilityHint(loc("list.detail.dismiss_bulk.hint"))

                if let account = accountStore.activeAccount,
                   let appPassword = accountStore.appPassword(for: account),
                   let result = viewModel.bulkActionResult,
                   !result.failures.isEmpty
                {
                    Button(loc("list.detail.retry_failed")) {
                        Task {
                            await viewModel.retryFailures(
                                from: result,
                                currentList: currentList,
                                comparisonList: comparisonList,
                                account: account,
                                appPassword: appPassword,
                                using: blueskyClient
                            )
                            syncSnapshot()
                        }
                    }
                    .accessibilityHint(loc("list.detail.retry_failed.hint"))
                }
            } message: {
                if let result = viewModel.bulkActionResult {
                    Text(bulkActionMessage(for: result))
                }
            }
            .confirmationDialog(
                loc("list.detail.delete_confirm"),
                isPresented: $isShowingDeleteConfirmation,
                titleVisibility: .visible
            ) {
                Button(loc("actions.delete"), role: .destructive) {
                    if let account = accountStore.activeAccount,
                       let appPassword = accountStore.appPassword(for: account)
                    {
                        Task {
                            do {
                                try await blueskyClient.deleteList(
                                    list: currentList,
                                    account: account,
                                    appPassword: appPassword
                                )
                                onListUpdated?(currentList)
                                dismiss()
                            } catch {
                                viewModel.errorMessage = AppError.userMessage(from: error)
                            }
                        }
                    }
                }
                .accessibilityHint(loc("list.detail.delete_list.hint"))
                .accessibilityInputLabels([loc("actions.delete")])
                Button(loc("actions.cancel"), role: .cancel) {}
                    .accessibilityHint(loc("list.detail.cancel_delete.hint"))
                    .accessibilityInputLabels([loc("actions.cancel")])
            } message: {
                Text(verbatim: loc("list.detail.delete_message"))
            }
            .onChange(of: viewModel.bulkActionResult) { _, newResult in
                guard let newResult else { return }
                let entry = ModerationOperationLogEntry(
                    title: newResult.operation.title,
                    summary: newResult.summaryText,
                    succeededHandles: newResult.succeededActors.map(\.handle),
                    failedHandles: newResult.failures.map(\.actor.handle)
                )
                workspaceStore.recordOperation(entry)
            }
    }

    private var rootContent: some View {
        Group {
            if let account = accountStore.activeAccount,
               let appPassword = accountStore.appPassword(for: account)
            {
                content(account: account, appPassword: appPassword)
            } else {
                ContentUnavailableView(
                    loc("list.detail.missing_creds"),
                    systemImage: "key.slash",
                    description: Text(verbatim: loc("list.detail.missing_creds.desc"))
                )
            }
        }
        .onChange(of: memberSearchQuery) { _, newQuery in
            viewModel.updateMemberFilter(newQuery)
        }
        .onChange(of: viewModel.members) { _, _ in
            exportState.cachedExportFileURL = nil
        }
        .onChange(of: viewModel.comparisonReport) { _, _ in
            exportState.cachedDiffExportFileURL = nil
        }
    }

    @ToolbarContentBuilder
    private func toolbarContent() -> some ToolbarContent {
        if isOwnedList {
            ToolbarItem(placement: .topBarTrailing) {
                Button(role: .destructive) {
                    isShowingDeleteConfirmation = true
                } label: {
                    Label { Text(verbatim: loc("list.detail.delete")) } icon: { Image(systemName: "trash") }
                }
                .accessibilityHint(loc("list.detail.delete_list.hint"))
            }

            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    importState.isShowingEditSheet = true
                } label: {
                    Label { Text(verbatim: loc("list.detail.edit")) } icon: { Image(systemName: "pencil") }
                }
                .accessibilityHint(loc("list.detail.edit_list.hint"))
            }
        }

        ToolbarItem(placement: .topBarTrailing) {
            HStack(spacing: 16) {
                Menu {
                    Button {
                        isExporting = true
                        Task { await exportList(format: .csv) }
                    } label: {
                        Label { Text(verbatim: loc("list.search.export_csv_all")) } icon: { Image(systemName: "arrow.down.doc") }
                    }

                    Button {
                        isExporting = true
                        Task { await exportList(format: .json) }
                    } label: {
                        Label { Text(verbatim: loc("list.search.export_json_all")) } icon: { Image(systemName: "arrow.down.doc") }
                    }

                    Button {
                        isExporting = true
                        Task { await exportList(format: .xlsx) }
                    } label: {
                        Label { Text(verbatim: loc("list.export.excel")) } icon: { Image(systemName: "arrow.down.doc") }
                    }

                    Button {
                        isExporting = true
                        Task { await exportList(format: .ods) }
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

                Button {
                    Task {
                        guard let account = accountStore.activeAccount,
                              let appPassword = accountStore.appPassword(for: account) else { return }
                        await reloadListContext(account: account, appPassword: appPassword)
                    }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .disabled(isExporting || accountStore.activeAccount == nil)
            }
        }
    }

    private func importSheetContent() -> some View {
        ImportHandlesSheet { rawInput in
            if let account = accountStore.activeAccount,
               let appPassword = accountStore.appPassword(for: account)
            {
                Task {
                    await viewModel.prepareImportPreview(
                        from: rawInput,
                        sourceDescription: loc("list.import.pasted_input"),
                        account: account,
                        appPassword: appPassword,
                        using: blueskyClient
                    )
                }
            }
        }
    }

    @ViewBuilder
    private func importPreviewSheetContent() -> some View {
        if let importPreview = viewModel.importPreview,
           let account = accountStore.activeAccount,
           let appPassword = accountStore.appPassword(for: account)
        {
            ImportPreviewSheet(
                preview: importPreview,
                isImporting: viewModel.isImportingHandles || viewModel.isPreparingImportPreview
            ) {
                viewModel.discardImportPreview()
            } importAction: {
                Task {
                    await viewModel.commitImportPreview(
                        to: currentList,
                        account: account,
                        appPassword: appPassword,
                        using: blueskyClient
                    )
                    syncSnapshot()
                }
            }
        }
    }

    private func content(account: AppAccount, appPassword: String) -> some View {
        List {
            Section {
                HStack(alignment: .top, spacing: 14) {
                    if let avatarURL = currentList.avatarURL {
                        Button {
                            imagePreview = ImagePreviewCollection(urls: [avatarURL], initialIndex: 0)
                        } label: {
                            AsyncImage(url: avatarURL) { image in
                                image
                                    .resizable()
                                    .scaledToFill()
                            } placeholder: {
                                avatarPlaceholder
                            }
                            .frame(width: 48, height: 48)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(Color.white.opacity(0.18), lineWidth: 1)
                            }
                        }
                        .buttonStyle(.plain)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text(currentList.name)
                            .appFont(.title)
                            .lineLimit(2)
                            .minimumScaleFactor(0.5)
                        if !currentList.description.isEmpty, currentList.description != currentList.name {
                            Text(currentList.description)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        if !isOwnedList, let ownerActor {
                            HStack(spacing: 10) {
                                if let avatarURL = ownerActor.avatarURL {
                                    AsyncImage(url: avatarURL) { image in
                                        image
                                            .resizable()
                                            .scaledToFill()
                                    } placeholder: {
                                        Circle()
                                            .fill(Color.skyPrimary.opacity(0.16))
                                    }
                                    .frame(width: 28, height: 28)
                                    .clipShape(Circle())
                                } else {
                                    Circle()
                                        .fill(Color.skyPrimary.opacity(0.16))
                                        .frame(width: 28, height: 28)
                                        .overlay {
                                            Text(ownerActor.displayName?.prefix(1).uppercased() ?? "?")
                                                .font(.caption.weight(.bold))
                                                .foregroundStyle(Color.skyPrimary)
                                        }
                                }
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(ownerActor.displayName ?? ownerActor.handle)
                                        .font(.subheadline.weight(.semibold))
                                    Text("@\(ownerActor.handle)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding(.top, 8)
                        }
                    }
                }
                .padding(.vertical, 4)
            }

            BatchProgressSection(batchState: batchState, viewModel: viewModel)

            if isOwnedList {
                ListSearchSection(
                    viewModel: viewModel,
                    batchState: batchState,
                    searchQuery: $searchQuery,
                    currentList: currentList,
                    account: account,
                    appPassword: appPassword,
                    isShowingImportSheet: $importState.isShowingImportSheet,
                    isShowingImportFilePicker: $importState.isShowingImportFilePicker,
                    exportFileURL: exportFileURL,
                    syncSnapshot: { syncSnapshot() }
                )
            }

            ListMembersSection(
                viewModel: viewModel,
                batchState: batchState,
                memberSearchQuery: $memberSearchQuery,
                currentList: currentList,
                account: account,
                appPassword: appPassword,
                syncSnapshot: { syncSnapshot() }
            )

            Section {
                LabeledContent(loc("list.detail.members"), value: "\(currentList.memberCount ?? viewModel.members.count)")
            } header: {
                Text(verbatim: loc("list.detail.stats_section"))
            }
        }
        .listStyle(.insetGrouped)
        .task {
            await reloadListContext(account: account, appPassword: appPassword)
        }
        .task {
            await loadOwner()
        }
        .task(id: searchQuery) {
            do {
                try await Task.sleep(for: .milliseconds(300))
            } catch {
                return
            }

            await viewModel.search(
                query: searchQuery,
                account: account,
                appPassword: appPassword,
                using: blueskyClient
            )
        }
        .refreshable {
            await reloadListContext(account: account, appPassword: appPassword)
        }
    }

    private var bulkResultPresentedBinding: Binding<Bool> {
        Binding(
            get: { viewModel.bulkActionResult != nil },
            set: { isPresented in
                if !isPresented {
                    viewModel.bulkActionResult = nil
                }
            }
        )
    }

    private var importPreviewPresentedBinding: Binding<Bool> {
        Binding(
            get: { viewModel.importPreview != nil },
            set: { isPresented in
                if !isPresented {
                    viewModel.discardImportPreview()
                }
            }
        )
    }

    private func exportList(format: ExportFormat) async {
        guard let account = accountStore.activeAccount,
              let appPassword = accountStore.appPassword(for: account)
        else {
            isExporting = false
            return
        }

        exportProgressMessage = "Processing..."
        let members: [BlueskyListMember]
        do {
            members = try await blueskyClient.fetchListMembers(list: currentList, account: account, appPassword: appPassword)
        } catch {
            viewModel.errorMessage = AppError.userMessage(from: error)
            isExporting = false
            exportProgressMessage = nil
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

        let sanitizedName = currentList.name.lowercased().replacingOccurrences(of: " ", with: "-")
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

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(sanitizedName)-full-export.\(format.rawValue)")
        try? data.write(to: url, options: .atomic)
        isExporting = false
        exportProgressMessage = nil
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

    @ViewBuilder
    private var avatarPlaceholder: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(Color.skyPrimary.opacity(0.12))
            .overlay {
                Image(systemName: currentList.kind.symbolName)
                    .font(.title3)
                    .foregroundStyle(Color.skyPrimary)
            }
    }

    private func loadOwner() async {
        guard !isOwnedList, let did = ownerDID else { return }
        do {
            let actors = try await LiveBlueskyClient.fetchProfileBatch(identifiers: [did], session: URLSession.shared)
            ownerActor = actors.first
        } catch {
            AppLogger.performance.error("Failed to fetch list owner: \(error.localizedDescription, privacy: .public)")
        }
    }
}

extension ListDetailView {
    enum ExportFormat: String, CaseIterable {
        case csv, json, xlsx, ods
    }
}

extension ListDetailView {
    struct BatchProgressSection: View {
        @ObservedObject var batchState: ListBatchProgressState
        let viewModel: ListDetailViewModel

        var body: some View {
            if let batchProgress = batchState.batchProgress {
                Section {
                    BatchProgressCard(
                        title: batchProgress.title,
                        completedCount: batchProgress.completedCount,
                        totalCount: batchProgress.totalCount,
                        currentHandle: batchProgress.currentHandle,
                        onCancel: { batchState.cancelBatch() }
                    )
                } header: {
                    Text(verbatim: loc("list.detail.bulk_operation"))
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
