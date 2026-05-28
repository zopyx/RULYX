import SwiftUI

// MARK: - InternalListDetailView

/// Detail view for an internal (local-only) list — shows members,
/// supports search, swipe-to-remove, CSV/JSON export, and editing.
struct InternalListDetailView: View {
    let list: InternalList
    @EnvironmentObject private var internalListStore: InternalListStore
    @EnvironmentObject private var localizationManager: LocalizationManager
    @Environment(\.dismiss) private var dismiss
    @State private var showDeleteConfirm = false
    @State private var showEditSheet = false
    @State private var editName: String
    @State private var editColor: InternalListColor
    @State private var searchText = ""
    @State private var exportFileURL: URL?

    init(list: InternalList) {
        self.list = list
        _editName = State(initialValue: list.name)
        _editColor = State(initialValue: list.color)
    }

    /// Filters members by search text against handle or display name.
    private var filteredMembers: [InternalListMember] {
        let members = internalListStore.lists.first(where: { $0.id == list.id })?.members ?? list.members
        guard !searchText.isEmpty else { return members }
        return members.filter {
            $0.handle.localizedCaseInsensitiveContains(searchText) ||
                ($0.displayName ?? "").localizedCaseInsensitiveContains(searchText)
        }
    }

    // MARK: - Body

    var body: some View {
        List {
            Section {
                if filteredMembers.isEmpty, !searchText.isEmpty {
                    EmptyStatePanel(
                        title: loc("list.members.no_matches"),
                        message: loc("list.members.no_matches_desc")
                    )
                } else if filteredMembers.isEmpty {
                    EmptyStatePanel(
                        title: loc("list.members.no_members"),
                        message: loc("list.members.no_members_desc")
                    )
                } else {
                    ForEach(filteredMembers) { member in
                        NavigationLink {
                            BlueskyProfileView(
                                member: BlueskyListMember(
                                    recordURI: "internal://\(list.id)/\(member.id)",
                                    actor: BlueskyActor(
                                        did: member.id,
                                        handle: member.handle,
                                        displayName: member.displayName,
                                        avatarURL: member.avatarURL.flatMap(URL.init)
                                    )
                                ),
                                list: nil
                            )
                        } label: {
                            HStack(spacing: 10) {
                                if let avatar = member.avatarURL, let url = URL(string: avatar) {
                                    ThumbnailImageView(url: url, maxPixelSize: 40) {
                                        Circle().fill(.quaternary)
                                    }
                                    .scaledToFill()
                                    .frame(width: 36, height: 36)
                                    .clipShape(Circle())
                                } else {
                                    Circle()
                                        .fill(list.color.colorValue.opacity(0.3))
                                        .frame(width: 36, height: 36)
                                        .overlay {
                                            Text(member.displayName?.prefix(1).uppercased() ?? member.handle.prefix(1).uppercased())
                                                .font(.caption.weight(.semibold))
                                                .foregroundStyle(list.color.colorValue)
                                        }
                                }
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(member.displayName ?? member.handle)
                                        .font(.subheadline)
                                    Text(member.handle)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                if let current = internalListStore.lists.first(where: { $0.id == list.id }) {
                                    internalListStore.removeMember(did: member.id, from: current.id)
                                }
                            } label: {
                                Label(loc("actions.remove"), systemImage: "trash")
                            }
                        }
                    }
                }
            } header: {
                HStack {
                    Circle()
                        .fill(list.color.colorValue)
                        .frame(width: 10, height: 10)
                    Text(list.name)
                    Spacer()
                    Text(loc("internal.list.member_count").replacingOccurrences(of: "{n}", with: "\(list.memberCount)"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: loc("list.search.placeholder"))
        .pageTitle(list.name)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        exportCSV()
                    } label: {
                        Label("CSV", systemImage: "doc.text")
                    }
                    Button {
                        exportJSON()
                    } label: {
                        Label("JSON", systemImage: "doc.text")
                    }
                    Divider()
                    Button {
                        showEditSheet = true
                    } label: {
                        Label(loc("internal.list.edit"), systemImage: "pencil")
                    }
                    Button(role: .destructive) {
                        showDeleteConfirm = true
                    } label: {
                        Label(loc("internal.list.delete"), systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.body.weight(.medium))
                }
                .accessibilityLabel(loc("list.detail.more_actions"))
            }
        }
        .alert(loc("internal.list.delete_confirm"), isPresented: $showDeleteConfirm) {
            Button(loc("internal.list.delete"), role: .destructive) {
                internalListStore.deleteList(list)
                dismiss()
            }
            Button(loc("actions.cancel"), role: .cancel) {}
        } message: {
            Text(loc("internal.list.delete_message"))
        }
        .sheet(isPresented: .init(get: { exportFileURL != nil }, set: { if !$0 { exportFileURL = nil } })) {
            if let url = exportFileURL {
                ShareSheet(activityItems: [url])
            }
        }
        .sheet(isPresented: $showEditSheet) {
            NavigationStack {
                Form {
                    Section {
                        TextField(loc("internal.lists.name"), text: $editName)
                        Picker(loc("internal.lists.color"), selection: $editColor) {
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
                .pageTitle(loc("internal.list.edit"))
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(loc("actions.save")) {
                            if let current = internalListStore.lists.first(where: { $0.id == list.id }) {
                                var updated = current
                                updated.name = editName
                                updated.color = editColor
                                internalListStore.updateList(updated)
                            }
                            showEditSheet = false
                        }
                        .disabled(editName.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                    ToolbarItem(placement: .cancellationAction) {
                        Button(loc("actions.cancel")) { showEditSheet = false }
                    }
                }
            }
            .presentationDetents([.medium])
        }
    }

    // MARK: - Export

    private func exportCSV() {
        let members = internalListStore.lists.first(where: { $0.id == list.id })?.members ?? list.members
        let header = "handle,display_name,did"
        let rows = members.map { member in
            "\(member.handle.csvField),\((member.displayName ?? "").csvField),\(member.id.csvField)"
        }
        let csv = ([header] + rows).joined(separator: "\n")
        writeAndShare(data: Data(csv.utf8), name: "\(list.name.lowercased().replacingOccurrences(of: " ", with: "-"))-internal.csv")
    }

    private func exportJSON() {
        let members = internalListStore.lists.first(where: { $0.id == list.id })?.members ?? list.members
        let objects = members.map { member -> [String: Any] in
            [
                "handle": member.handle,
                "display_name": member.displayName ?? "",
                "did": member.id,
            ]
        }
        if let data = try? JSONSerialization.data(withJSONObject: objects, options: [.prettyPrinted, .sortedKeys]) {
            writeAndShare(data: data, name: "\(list.name.lowercased().replacingOccurrences(of: " ", with: "-"))-internal.json")
        }
    }

    /// Writes data to a temp file and triggers the share sheet.
    private func writeAndShare(data: Data, name: String) {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        try? data.write(to: url, options: .atomic)
        exportFileURL = url
    }
}

// MARK: - ShareSheet

/// Bridge to UIActivityViewController for sharing exported files.
private struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context _: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_: UIActivityViewController, context _: Context) {}
}
