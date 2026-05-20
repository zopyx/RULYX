import SwiftUI

struct HTTPRequestDebugView: View {
    @EnvironmentObject private var debugStore: HTTPRequestDebugStore
    @EnvironmentObject private var localizationManager: LocalizationManager
    @Environment(\.dismiss) private var dismiss
    @State private var selectedFilter: HTTPRequestDebugFilter = .succeeded
    @State private var selectedErrorEntry: HTTPRequestDebugEntry?

    var body: some View {
        VStack(spacing: 0) {
            Picker("Filter", selection: $selectedFilter) {
                ForEach(HTTPRequestDebugFilter.allCases) { filter in
                    Text(localizationManager.localized(filter.titleKey)).tag(filter)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.top, 8)

            List {
                if filteredEntries.isEmpty {
                    ContentUnavailableView(
                        localizationManager.localized("debug.http.title"),
                        systemImage: selectedFilter == .failed ? "exclamationmark.triangle" : "checkmark.circle",
                        description: Text(localizationManager.localized("debug.http.empty"))
                    )
                } else {
                    ForEach(filteredEntries) { entry in
                        HTTPRequestDebugRow(
                            entry: entry,
                            localizationManager: localizationManager,
                            onSelectErrorPayload: {
                                selectedErrorEntry = entry
                            }
                        )
                    }
                }
            }
        }
        .navigationTitle(localizationManager.localized("debug.http.title"))
        .sheet(item: $selectedErrorEntry) { entry in
            NavigationStack {
                HTTPRequestDebugErrorResponseView(entry: entry)
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                .accessibilityLabel(loc("actions.close"))
            }
        }
    }
}

private struct HTTPRequestDebugErrorResponseView: View {
    let entry: HTTPRequestDebugEntry
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            Text(verbatim: entry.errorResponseJSON ?? "")
                .font(.body.monospaced())
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .textSelection(.enabled)
        }
        .navigationTitle(entry.url)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                .accessibilityLabel(localizationManager.localized("actions.close"))
            }
        }
    }
}

#Preview {
    NavigationStack {
        HTTPRequestDebugView()
            .environmentObject(HTTPRequestDebugStore.shared)
            .environmentObject(LocalizationManager.shared)
    }
}
