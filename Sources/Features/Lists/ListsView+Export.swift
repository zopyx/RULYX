import SwiftUI

enum ListsExportFormat: String, CaseIterable {
    case csv, json, xlsx, ods
}

struct ListsShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context _: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_: UIActivityViewController, context _: Context) {}
}

extension ListsView {
    var exportListPickerSheet: some View {
        NavigationStack {
            let lists = allListsWithMembers
            List {
                if lists.isEmpty {
                    ContentUnavailableView(
                        loc("lists.export.no_members"),
                        systemImage: "arrow.down.doc",
                        description: Text(loc: "lists.export.no_members_desc")
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
                                    Text(
                                        verbatim: locPlural("members_count", count: count)
                                            .replacingOccurrences(of: "{count}", with: "\(count)")
                                    )
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
                    Button("actions.cancel") { isShowingListPicker = false }
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
                    ListsShareSheet(activityItems: [url])
                }
            }
            .onChange(of: shareFileURL) { _, url in
                if url != nil { showShareSheet = true }
            }
        }
    }

    var allListsWithMembers: [BlueskyList] {
        viewModel.listsByKind.values
            .flatMap(\.self)
            .filter { ($0.memberCount ?? 0) > 0 }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    func performExport(list: BlueskyList) async {
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

    func generateCSV(from members: [BlueskyListMember], stats: [String: (followers: Int, following: Int, posts: Int, description: String)] = [:]) -> String {
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

    func generateJSON(from members: [BlueskyListMember], stats: [String: (followers: Int, following: Int, posts: Int, description: String)] = [:]) -> Data {
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
