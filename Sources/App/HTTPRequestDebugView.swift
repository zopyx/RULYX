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
                Button(localizationManager.localized("debug.http.close")) {
                    dismiss()
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button(localizationManager.localized("debug.http.clear")) {
                    Task {
                        await debugStore.clear()
                    }
                }
                .disabled(debugStore.entries.isEmpty)
            }
        }
    }

    private var filteredEntries: [HTTPRequestDebugEntry] {
        debugStore.entries.filter { entry in
            switch selectedFilter {
            case .succeeded:
                entry.state != .failed
            case .failed:
                entry.state == .failed
            }
        }
    }
}

private enum HTTPRequestDebugFilter: String, CaseIterable, Identifiable {
    case succeeded
    case failed

    var id: String {
        rawValue
    }

    var titleKey: String {
        switch self {
        case .succeeded:
            "debug.http.state.succeeded"
        case .failed:
            "debug.http.state.failed"
        }
    }
}

private struct HTTPRequestDebugRow: View {
    let entry: HTTPRequestDebugEntry
    let localizationManager: LocalizationManager
    let onSelectErrorPayload: () -> Void

    var body: some View {
        rowContent
            .contentShape(Rectangle())
            .highPriorityGesture(
                TapGesture(count: 2)
                    .onEnded {
                        guard isErrorPayloadAvailable else { return }
                        onSelectErrorPayload()
                    }
            )
            .padding(.vertical, 4)
    }

    private var rowContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(verbatim: "#\(entry.sequenceNumber)")
                        .font(.caption2.monospacedDigit().weight(.semibold))
                        .foregroundStyle(.secondary)

                    if let source = entry.source, !source.isEmpty {
                        Text(verbatim: source)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.primary)
                    }

                    if let origin = entry.origin, !origin.isEmpty {
                        Text(verbatim: origin)
                            .font(.caption2.monospaced())
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .textSelection(.enabled)
                    }

                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(verbatim: entry.method)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)

                        Text(verbatim: entry.url)
                            .font(.caption.monospaced())
                            .fixedSize(horizontal: false, vertical: true)
                            .textSelection(.enabled)
                    }
                }

                Spacer(minLength: 8)

                VStack(alignment: .trailing, spacing: 6) {
                    Text(localizationManager.localized(stateKey))
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(stateColor.opacity(0.15), in: Capsule())
                        .foregroundStyle(stateColor)

                    if isErrorPayloadAvailable {
                        Image(systemName: "chevron.right")
                            .flipsForRightToLeftLayoutDirection(true)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }
            }

            HStack(spacing: 12) {
                Text(entry.startedAt.formatted(date: .omitted, time: .standard))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)

                if let duration = entry.duration {
                    Text(verbatim: Self.durationString(from: duration))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }

                if let statusCode = entry.statusCode {
                    Text(verbatim: "\(statusCode)")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(statusCodeColor(statusCode))
                }
            }

            if let errorMessage = entry.errorMessage, !errorMessage.isEmpty {
                Text(verbatim: errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
            }
        }
    }

    private var isErrorPayloadAvailable: Bool {
        entry.state == .failed && !(entry.errorResponseJSON?.isEmpty ?? true)
    }

    private var stateKey: String {
        switch entry.state {
        case .running:
            "debug.http.state.running"
        case .succeeded:
            "debug.http.state.succeeded"
        case .failed:
            "debug.http.state.failed"
        }
    }

    private var stateColor: Color {
        switch entry.state {
        case .running:
            .orange
        case .succeeded:
            .green
        case .failed:
            .red
        }
    }

    private func statusCodeColor(_ statusCode: Int) -> Color {
        if (200 ..< 300).contains(statusCode) {
            return .green
        }
        if (400 ..< 600).contains(statusCode) {
            return .red
        }
        return .secondary
    }

    private static func durationString(from duration: TimeInterval) -> String {
        let milliseconds = duration * 1000
        if milliseconds >= 100 {
            return String(format: "%.0f ms", milliseconds)
        }
        if milliseconds >= 10 {
            return String(format: "%.1f ms", milliseconds)
        }
        return String(format: "%.2f ms", milliseconds)
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
                    Image(systemName: "xmark")
                }
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
