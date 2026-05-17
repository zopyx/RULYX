import SwiftUI

struct ActivityLogView: View {
    @EnvironmentObject private var workspaceStore: ModerationWorkspaceStore
    @State private var searchQuery = ""
    @State private var selectedType: String?

    private var types: [String] {
        Array(Set(workspaceStore.operationLog.map(\.title))).sorted()
    }

    private var filtered: [ModerationOperationLogEntry] {
        let q = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return workspaceStore.operationLog.filter { entry in
            if let selectedType, entry.title != selectedType { return false }
            if q.isEmpty { return true }
            return entry.title.lowercased().contains(q) ||
                entry.summary.lowercased().contains(q) ||
                entry.succeededHandles.contains(where: { $0.lowercased().contains(q) }) ||
                entry.failedHandles.contains(where: { $0.lowercased().contains(q) })
        }
    }

    var body: some View {
        List {
            Section {
                TextField(loc("activity.search"), text: $searchQuery)
                    .textInputAutocapitalization(.never)
            }

            if !types.isEmpty {
                Section {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            FilterChip(title: loc("activity.all"), isSelected: selectedType == nil) { selectedType = nil }
                                .accessibilityHint("Shows all activity types")
                            ForEach(types, id: \.self) { type in
                                FilterChip(title: type, isSelected: selectedType == type) { selectedType = type }
                                    .accessibilityHint("Filters activity by \(type)")
                            }
                        }
                        .padding(.horizontal, 4)
                    }
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                } header: {
                    Text(verbatim: loc("activity.filter_by_type"))
                }
            }

            if filtered.isEmpty {
                ContentUnavailableView(loc("activity.no_matches"), systemImage: "magnifyingglass", description: Text(verbatim: loc("activity.no_matches_desc")))
            } else {
                ForEach(filtered) { entry in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(entry.title).font(.subheadline.weight(.semibold))
                            Spacer()
                            Text(entry.createdAt, style: .date).font(.caption).foregroundStyle(.secondary)
                        }
                        Text(entry.summary).font(.caption).foregroundStyle(.secondary)
                        if !entry.failedHandles.isEmpty {
                            Text(verbatim: loc("activity.failed_format").replacingOccurrences(of: "{handles}", with: entry.failedHandles.joined(separator: ", ")))
                                .font(.caption2).foregroundStyle(.red)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(loc("activity.title"))
    }
}

private struct FilterChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(isSelected ? .white : Color.skyPrimary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(isSelected ? Color.skyPrimary : Color.skyPrimary.opacity(0.12))
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    NavigationStack {
        ActivityLogView()
            .environmentObject(ModerationWorkspaceStore(preview: true))
    }
}
