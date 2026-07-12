import SwiftUI

// MARK: - AutoBlockListPickerView

/// Multi-select list picker for configuring which lists automatically receive
/// newly blocked-back actors. Selection is persisted via `@AppStorage`.
struct AutoBlockListPickerView: View {
    @EnvironmentObject private var container: BlueskyServiceContainerWrapper
    @EnvironmentObject private var accountStore: AccountStore
    @EnvironmentObject private var internalListStore: InternalListStore
    @EnvironmentObject private var localizationManager: LocalizationManager

    @AppStorage("autoBlockTargetListIDs") private var selectedIDsData: Data = Data()

    @State private var allLists: [BlueskyList] = []
    @State private var selectedIDs: Set<String> = []
    @State private var isLoading = true

    // MARK: - Body

    var body: some View {
        Group {
            if isLoading {
                ProgressView(loc("rel.loading_lists"))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if allLists.isEmpty {
                ContentUnavailableView(
                    loc("rel.no_lists_title"),
                    systemImage: "tray",
                    description: Text(loc: "rel.no_lists_desc")
                )
            } else {
                List {
                    let moderationLists = allLists.filter { $0.kind == .moderation }
                    if !moderationLists.isEmpty {
                        Section(loc("lists.moderation_lists")) {
                            ForEach(moderationLists) { list in
                                listRow(list)
                            }
                        }
                    }

                    let internalLists = allLists.filter { $0.kind == .internal }
                    if !internalLists.isEmpty {
                        Section(loc("lists.internal_lists")) {
                            ForEach(internalLists) { list in
                                listRow(list)
                            }
                        }
                    }

                    let regularLists = allLists.filter { $0.kind == .regular }
                    if !regularLists.isEmpty {
                        Section(loc("lists.lists")) {
                            ForEach(regularLists) { list in
                                listRow(list)
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .pageTitle(loc("settings.autoblock.lists"))
        .task {
            await loadLists()
        }
        .onDisappear {
            persistSelection()
        }
    }

    // MARK: - Helpers

    private func listRow(_ list: BlueskyList) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(list.name)
                    .font(.subheadline.weight(.medium))
                Text(list.kind.title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let count = list.memberCount {
                    Text(loc("internal.list.member_count").replacingOccurrences(of: "{n}", with: "\(count)"))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            Spacer()
            if selectedIDs.contains(list.id) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Color.skyPrimary)
                    .font(.title3)
            } else {
                Image(systemName: "circle")
                    .foregroundStyle(.tertiary)
                    .font(.title3)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            toggle(list.id)
        }
    }

    private func toggle(_ id: String) {
        if selectedIDs.contains(id) {
            selectedIDs.remove(id)
        } else {
            selectedIDs.insert(id)
        }
    }

    private func persistSelection() {
        let ids = Array(selectedIDs)
        if let data = try? JSONEncoder().encode(ids) {
            selectedIDsData = data
        }
    }

    private func loadLists() async {
        defer { isLoading = false }

        // Restore previous selection
        if let ids = try? JSONDecoder().decode([String].self, from: selectedIDsData) {
            selectedIDs = Set(ids)
        }

        var lists: [BlueskyList] = []
        if let account = accountStore.activeAccount,
           let appPassword = accountStore.appPassword(for: account) {
            do {
                lists = try await container.blueskyClient.fetchLists(for: account, appPassword: appPassword)
            } catch {
                AppLogger.moderation.error("Failed to load lists for auto-block picker: \(error.localizedDescription, privacy: .public)")
            }
        }

        let internalLists = internalListStore.lists.map { internalList in
            BlueskyList(
                id: "internal:\(internalList.id.uuidString)",
                name: internalList.name,
                description: "Internal",
                memberCount: internalList.memberCount,
                kind: .internal,
                cid: nil
            )
        }
        lists.append(contentsOf: internalLists)

        allLists = lists.sorted { lhs, rhs in
            if lhs.kind != rhs.kind {
                return lhs.kind.sortOrder < rhs.kind.sortOrder
            }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        AutoBlockListPickerView()
            .environmentObject(PreviewBlueskyClient())
            .environmentObject(AccountStore(preview: true))
            .environmentObject(InternalListStore())
            .environmentObject(LocalizationManager.shared)
    }
}
