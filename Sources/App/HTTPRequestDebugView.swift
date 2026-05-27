import SwiftUI

/// Filter options for the HTTP request debug list.
enum HTTPRequestDebugFilter: String, CaseIterable, Identifiable {
    case succeeded
    case failed

    var id: String {
        rawValue
    }

    /// Localization key for the filter's display title.
    var titleKey: String {
        switch self {
        case .succeeded: "debug.http.state.succeeded"
        case .failed: "debug.http.state.failed"
        }
    }

    func matches(_ entry: HTTPRequestDebugEntry) -> Bool {
        switch self {
        case .succeeded: entry.state == .succeeded
        case .failed: entry.state == .failed
        }
    }
}

/// A debug view that displays logged HTTP requests, their status codes,
/// durations, and error response bodies. Supports filtering by succeeded/failed.
struct HTTPRequestDebugView: View {
    @EnvironmentObject private var debugStore: HTTPRequestDebugStore
    @EnvironmentObject private var localizationManager: LocalizationManager
    @Environment(\.dismiss) private var dismiss
    @State private var selectedFilter: HTTPRequestDebugFilter = .succeeded
    @State private var selectedErrorEntry: HTTPRequestDebugEntry?

    private var filteredEntries: [HTTPRequestDebugEntry] {
        debugStore.entries.filter { selectedFilter.matches($0) }
    }

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
            ToolbarItem(placement: .topBarTrailing) {
                ToolbarCloseButton()
            }
        }
    }
}

/// A single row displaying a logged HTTP request's URL, method, status,
/// duration, source, and an optional "View Error" button.
private struct HTTPRequestDebugRow: View {
    let entry: HTTPRequestDebugEntry
    let localizationManager: LocalizationManager
    let onSelectErrorPayload: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.url)
                    .font(.caption.monospaced())
                    .lineLimit(2)
                    .truncationMode(.middle)
                HStack(spacing: 6) {
                    Text(entry.method)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text("#\(entry.sequenceNumber)  \(entry.startedAt, format: .dateTime.day(.twoDigits).month(.twoDigits))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                    if let code = entry.statusCode {
                        Text("\(code)")
                            .font(.caption2)
                            .foregroundStyle(code < 400 ? .green : .red)
                    }
                    if let duration = entry.duration {
                        Text(String(format: "%.1fs", duration))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                if let source = entry.source {
                    Text(source)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            Spacer()
            if entry.state == .failed, entry.errorResponseJSON != nil {
                Button("View Error", action: onSelectErrorPayload)
                    .font(.caption)
                    .buttonStyle(.bordered)
            }
        }
        .padding(.vertical, 2)
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
        .toolbarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                ToolbarCloseButton()
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
