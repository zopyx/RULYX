import SwiftUI

// MARK: - ListedOnListsView

/// Lists that a given profile belongs to, from the public index plus AppView metadata.
/// Shows list name, description, owner handle, member count, and relative date added.
///
/// The walk behind this screen is long for a well-listed profile — one metadata request per
/// owning repo — so the view renders three states: **loading** (with a determinate bar once
/// the number of lists is known), **empty**, and **content**. While the walk is still running
/// a progress row stays above the already-resolved entries, and rows whose member count is
/// still loading say so.
struct ListedOnListsView: View {
    /// The entries resolved so far; the array can grow while `isLoading` is true.
    let entries: [ListedOnListEntry]
    /// True while the "listed on" walk is still running.
    var isLoading = false
    /// Progress of the running walk, when known.
    var progress: ListedOnProgress?
    /// Error from the walk; shown when nothing could be loaded at all.
    var errorMessage: String?

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var accountStore: AccountStore
    @EnvironmentObject private var container: BlueskyServiceContainerWrapper
    @EnvironmentObject private var localizationManager: LocalizationManager
    @State private var ownerHandles: [String: String] = [:]
    @State private var memberCounts: [String: Int] = [:]
    @State private var isLoadingCounts = false

    /// Entries sorted newest-first by date added.
    private var sortedEntries: [ListedOnListEntry] {
        entries.sorted { a, b in
            date(from: a.dateAdded) > date(from: b.dateAdded)
        }
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            Group {
                if sortedEntries.isEmpty, isLoading {
                    loadingPanel
                } else if sortedEntries.isEmpty, let errorMessage {
                    EmptyStatePanel(title: loc("lists.listed_on.empty"), message: errorMessage)
                } else if sortedEntries.isEmpty {
                    EmptyStatePanel(title: loc("lists.listed_on.empty"))
                } else {
                    List {
                        if isLoading {
                            Section {
                                progressRow
                            }
                        }
                        Section {
                            ForEach(sortedEntries) { entry in
                                NavigationLink {
                                    ListDetailView(
                                        list: blueskyList(from: entry),
                                        onListUpdated: { _ in }
                                    )
                                    .environmentObject(accountStore)
                                } label: {
                                    rowContent(entry)
                                }
                            }
                        }
                    }
                }
            }
            .pageTitle(loc("lists.lists_on_profile"))
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    ToolbarCloseButton()
                }
            }
            .task {
                await loadOwnerHandles()
                if let account = accountStore.activeAccount,
                   let appPassword = accountStore.appPassword(for: account)
                {
                    await loadMemberCounts(account: account, appPassword: appPassword)
                }
            }
        }
    }

    // MARK: - Loading states

    /// Fills the screen while nothing has resolved yet: a determinate bar once the list count
    /// is known, a spinner during the (open-ended) membership walk before that.
    @ViewBuilder private var loadingPanel: some View {
        if case let .lists(resolved, total) = progress, total > 0 {
            VStack(spacing: 12) {
                ProgressView(value: Double(resolved), total: Double(total))
                    .progressViewStyle(.linear)
                Text(progressCaption)
                    .appFont(.label)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .frame(maxWidth: .infinity, minHeight: 120)
            .padding()
            .accessibilityElement(children: .combine)
        } else {
            LoadingPanel(message: loc("lists.listed_on.loading_memberships"))
        }
    }

    /// Sits above the entries while the walk is still running, so a partial screen still
    /// shows that more is coming.
    private var progressRow: some View {
        HStack(spacing: 10) {
            if let fraction = progress?.fraction {
                ProgressView(value: fraction)
                    .progressViewStyle(.linear)
            } else {
                ProgressView()
                    .scaleEffect(0.6)
            }
            Text(progressCaption)
                .appFont(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .accessibilityElement(children: .combine)
    }

    /// Localized caption of the current phase: "12 of 150 lists" once the count is known.
    private var progressCaption: String {
        switch progress {
        case .memberships, .none:
            loc("lists.listed_on.loading_memberships")
        case let .lists(resolved, total):
            loc("lists.listed_on.loading_lists")
                .replacingOccurrences(of: "{done}", with: "\(resolved)")
                .replacingOccurrences(of: "{total}", with: "\(total)")
        }
    }

    // MARK: - Rows

    /// Converts a listed-on entry into a `BlueskyList` model for navigation.
    private func blueskyList(from entry: ListedOnListEntry) -> BlueskyList {
        BlueskyList(
            id: atURI(from: entry.url, ownerDID: entry.did) ?? entry.url,
            name: entry.name,
            description: entry.description ?? "",
            memberCount: memberCounts[entry.url],
            kind: .regular,
            avatarURL: nil
        )
    }

    /// Displays the list name, description, owner handle, member count, and relative date.
    private func rowContent(_ entry: ListedOnListEntry) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(entry.name)
                        .lineLimit(1)
                }
                if let desc = entry.description, !desc.isEmpty {
                    Text(desc)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                if let count = memberCounts[entry.url] {
                    Text(loc("internal.list.member_count").replacingOccurrences(of: "{n}", with: "\(count)"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if isLoadingCounts {
                    // The member count comes from its own per-list request: say so instead of
                    // leaving the row looking like it simply has no members.
                    HStack(spacing: 4) {
                        ProgressView()
                            .scaleEffect(0.5)
                        Text(loc("lists.listed_on.loading_member_counts"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .combine)
                }
                if let handle = ownerHandles[entry.url] {
                    Text(handle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Text(formatDateRelative(dateString: entry.dateAdded))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Enrichment

    /// Resolves the DID for each entry to a human-readable handle via batch profile fetch.
    private func loadOwnerHandles() async {
        let dids = Set(entries.map(\.did))
        guard !dids.isEmpty else { return }
        do {
            let actors = try await LiveBlueskyClient.fetchProfileBatch(identifiers: Array(dids), httpClient: HTTPClient())
            for actor in actors {
                for entry in entries where entry.did == actor.did {
                    ownerHandles[entry.url] = actor.handle
                }
            }
        } catch {
            AppLogger.performance.error("Failed to fetch owner handles: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Fetches member counts for each list from the Bluesky API in parallel.
    private func loadMemberCounts(account: AppAccount, appPassword: String) async {
        isLoadingCounts = true
        defer { isLoadingCounts = false }

        await withTaskGroup(of: (String, Int?).self) { group in
            for entry in entries {
                guard let atURI = atURI(from: entry.url, ownerDID: entry.did) else { continue }
                group.addTask {
                    do {
                        let (list, _) = try await container.list.fetchListDetails(
                            uri: atURI,
                            account: account,
                            appPassword: appPassword
                        )
                        return (entry.url, list.memberCount)
                    } catch {
                        return (entry.url, nil)
                    }
                }
            }

            for await (url, count) in group {
                if let count {
                    memberCounts[url] = count
                }
            }
        }
    }

    /// Formats a date string relative to now (< 28 days) or as an abbreviated date.
    private func formatDateRelative(dateString: String) -> String {
        guard let date = SharedDateFormatters.parseISO8601(dateString) else { return dateString }

        let daysSince = Calendar.current.dateComponents([.day], from: date, to: Date()).day ?? 0
        if daysSince < 28 {
            let relativeFormatter = RelativeDateTimeFormatter()
            relativeFormatter.unitsStyle = .short
            relativeFormatter.locale = Locale(identifier: LocalizationManager.shared.currentLanguage)
            return relativeFormatter.localizedString(for: date, relativeTo: Date())
        }
        return date.formatted(date: .abbreviated, time: .omitted)
    }

    /// Parses an ISO 8601 string to Date, returning distantPast on failure.
    private func date(from string: String) -> Date {
        SharedDateFormatters.parseISO8601(string) ?? .distantPast
    }
}

/// Builds an AT URI from a list URL and owner DID.
private func atURI(from url: String, ownerDID: String) -> String? {
    let parts = url.split(separator: "/")
    guard parts.count >= 2, let rkey = parts.last else { return nil }
    return "at://\(ownerDID)/app.bsky.graph.list/\(rkey)"
}
