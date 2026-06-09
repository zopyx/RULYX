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

// MARK: - Row

/// A single row displaying a logged HTTP request.
///
/// Layout:
///   Line 1: <METHOD> <URL>
///   Line 2: <status>  <ISO8601 timestamp>  <duration ms>
///   Line 3: <source>
///   Line 4 (failed only): [Response] button
private struct HTTPRequestDebugRow: View {
    let entry: HTTPRequestDebugEntry
    let onSelectErrorPayload: () -> Void

    private var iso8601: DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZ"
        return f
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Line 1: HTTP method + URL
            HStack(spacing: 4) {
                Text(entry.method)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(entry.url)
                    .font(.caption.monospaced())
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            // Line 2: status, ISO8601 timestamp, duration ms
            HStack(spacing: 8) {
                if let code = entry.statusCode {
                    Text("\(code)")
                        .font(.caption2.monospacedDigit().weight(.semibold))
                        .foregroundStyle(code < 400 ? .green : .red)
                } else {
                    Text("---")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.tertiary)
                }

                Text(entry.startedAt, formatter: iso8601)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)

                if let duration = entry.duration {
                    Text("\(Int(duration * 1000))ms")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                } else {
                    Text("running…")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.tertiary)
                }
            }

            // Line 3: source (originator)
            if let source = entry.source {
                Text(source)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            // Line 4: Response button (failed only)
            if entry.state == .failed {
                Button("Response", action: onSelectErrorPayload)
                    .font(.caption.weight(.medium))
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .tint(.red)
            }
        }
        .padding(.vertical, 6)
    }
}

// MARK: - Error detail sheet

private struct HTTPRequestDebugErrorResponseView: View {
    let entry: HTTPRequestDebugEntry
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Status code
                if let code = entry.statusCode {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Status")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text("\(code)")
                            .font(.title.weight(.bold))
                            .foregroundStyle(.red)
                    }
                }

                // Error message
                if let errorMessage = entry.errorMessage {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Error")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text(errorMessage)
                            .font(.body)
                            .foregroundStyle(.red)
                    }
                }

                // Response body
                if let json = entry.errorResponseJSON {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Response Body")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text(verbatim: json)
                            .font(.body.monospaced())
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding()
                            .background(Color(.systemGray6))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }

                // URL for context
                VStack(alignment: .leading, spacing: 2) {
                    Text("URL")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(entry.url)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }

                // Timestamp
                VStack(alignment: .leading, spacing: 2) {
                    Text("Timestamp")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(entry.startedAt, format: .dateTime)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding()
        }
        .navigationTitle("Response Details")
        .navigationBarTitleDisplayMode(.inline)
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
