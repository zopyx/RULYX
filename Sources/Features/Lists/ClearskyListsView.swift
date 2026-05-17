import SwiftUI

struct ClearskyListsView: View {
    let entries: [ClearskyListEntry]
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var accountStore: AccountStore
    @EnvironmentObject private var blueskyClient: LiveBlueskyClient
    @State private var ownerHandles: [String: String] = [:]

    private var sortedEntries: [ClearskyListEntry] {
        entries.sorted { a, b in
            date(from: a.dateAdded) > date(from: b.dateAdded)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(sortedEntries) { entry in
                        NavigationLink {
                            ListDetailView(
                                list: blueskyList(from: entry),
                                onListUpdated: { _ in }
                            )
                            .environmentObject(accountStore)
                            .environmentObject(blueskyClient)
                        } label: {
                            rowContent(entry)
                        }
                    }
                }
            }
            .navigationTitle(loc("lists.lists_on_profile"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title3)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            .task {
                await loadOwnerHandles()
            }
        }
    }

    private func blueskyList(from entry: ClearskyListEntry) -> BlueskyList {
        BlueskyList(
            id: atURI(from: entry.url, ownerDID: entry.did) ?? entry.url,
            name: entry.name,
            description: entry.description ?? "",
            memberCount: nil,
            kind: .regular,
            avatarURL: nil
        )
    }

    private func rowContent(_ entry: ClearskyListEntry) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(entry.name)
                        .lineLimit(1)
                }
                if let handle = ownerHandles[entry.url] {
                    Text(handle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let desc = entry.description, !desc.isEmpty {
                    Text(desc)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(2)
                }
            }
            Spacer()
            Text(formatDateRelative(dateString: entry.dateAdded))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func loadOwnerHandles() async {
        let dids = Set(entries.map(\.did))
        guard !dids.isEmpty else { return }
        do {
            let actors = try await LiveBlueskyClient.fetchProfileBatch(identifiers: Array(dids), session: URLSession.shared)
            for actor in actors {
                for entry in entries where entry.did == actor.did {
                    ownerHandles[entry.url] = actor.handle
                }
            }
        } catch {
            AppLogger.performance.error("Failed to fetch owner handles: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func formatDateRelative(dateString: String) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let date = formatter.date(from: dateString) ?? {
            formatter.formatOptions = [.withInternetDateTime]
            return formatter.date(from: dateString)
        }() else { return dateString }

        let daysSince = Calendar.current.dateComponents([.day], from: date, to: Date()).day ?? 0
        if daysSince < 28 {
            let relativeFormatter = RelativeDateTimeFormatter()
            relativeFormatter.unitsStyle = .short
            relativeFormatter.locale = Locale(identifier: LocalizationManager.shared.currentLanguage)
            return relativeFormatter.localizedString(for: date, relativeTo: Date())
        }
        return date.formatted(date: .abbreviated, time: .omitted)
    }

    private func date(from string: String) -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: string) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        if let date = formatter.date(from: string) { return date }
        return .distantPast
    }
}

private func atURI(from url: String, ownerDID: String) -> String? {
    let parts = url.split(separator: "/")
    guard parts.count >= 2, let rkey = parts.last else { return nil }
    return "at://\(ownerDID)/app.bsky.graph.list/\(rkey)"
}
