import Charts
import SwiftUI

/// Dashboard view showing moderation activity stats — operations by type,
/// recent operation log, and top moderated accounts.
///
/// Adapts to horizontal size class:
/// - `.regular` (iPad landscape): grid layout with card-style panels
/// - `.compact` (iPhone / iPad Slide Over): single-column list layout
struct DashboardView: View {
    @EnvironmentObject private var accountStore: AccountStore
    @EnvironmentObject private var workspaceStore: ModerationWorkspaceStore
    @EnvironmentObject private var localizationManager: LocalizationManager
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private let columns = [
        GridItem(.adaptive(minimum: 300, maximum: 450), spacing: 16),
    ]

    // MARK: - Body

    var body: some View {
        if horizontalSizeClass == .regular {
            regularBody
        } else {
            compactBody
        }
    }

    // MARK: - Compact (iPhone / Slide Over)

    private var compactBody: some View {
        List {
            Section {
                LabeledContent(loc("dashboard.accounts"), value: "\\(accountStore.accounts.count)")
                LabeledContent(loc("dashboard.total_ops"), value: "\\(workspaceStore.operationLog.count)")
            } header: {
                Text(loc: "dashboard.overview")
            }

            if !workspaceStore.operationLog.isEmpty {
                Section {
                    Chart(operationCounts, id: \.0) { type, count in
                        BarMark(x: .value("Type", type), y: .value("Count", count))
                            .foregroundStyle(Color.skyPrimary.gradient)
                    }
                    .frame(height: 180)
                    .chartXAxis { AxisMarks { AxisValueLabel() } }
                } header: {
                    Text(loc: "dashboard.by_type")
                }

                Section {
                    ForEach(workspaceStore.operationLog.prefix(10)) { entry in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(entry.title).font(.subheadline.weight(.semibold))
                                Spacer()
                                Text(entry.createdAt, style: .date).font(.caption).foregroundStyle(.secondary)
                            }
                            Text(entry.summary).font(.caption).foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 2)
                    }
                } header: {
                    Text(loc: "dashboard.recent")
                }

                Section {
                    let top = topModeratedAccounts()
                    if top.isEmpty {
                        Text(loc: "dashboard.no_data_yet").foregroundStyle(.secondary)
                    } else {
                        ForEach(top.prefix(10), id: \.0) { handle, count in
                            HStack {
                                Text(handle).font(.subheadline.monospaced())
                                Spacer()
                                Text("\\(count)x").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                } header: {
                    Text(loc: "dashboard.top_moderated")
                }
            } else {
                ContentUnavailableView(loc("dashboard.no_data"), systemImage: "chart.bar", description: Text(loc: "dashboard.no_data_desc"))
            }
        }
        .listStyle(.insetGrouped)
        .pageTitle(loc("dashboard.title"))
    }

    // MARK: - Regular (iPad landscape)

    private var regularBody: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 16) {
                accountsCard
                    .gradientCardStyle()
                opsChartCard
                    .appCardStyle()
                topModeratedCard
                    .appCardStyle()
                if !workspaceStore.operationLog.isEmpty {
                    recentActivityCard
                        .appCardStyle()
                }
            }
            .padding()
        }
        .pageTitle(loc("dashboard.title"))
    }

    // MARK: - Card Views

    private var accountsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "person.circle.fill")
                    .font(.title2)
                    .foregroundStyle(Color.skyPrimary)
                Text(loc("dashboard.accounts"))
                    .font(.headline)
                Spacer()
                Text("\\(accountStore.accounts.count)")
                    .font(.largeTitle.weight(.bold))
                    .foregroundStyle(Color.skyPrimary)
            }
            if let active = accountStore.activeAccount {
                HStack {
                    Text(active.displayName)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(loc("dashboard.active"))
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Color.skyPrimary.opacity(0.15))
                        .clipShape(Capsule())
                }
            }
        }
        .padding()
    }

    private var opsChartCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "chart.bar.fill")
                    .font(.title2)
                    .foregroundStyle(Color.skyPrimary)
                Text(loc("dashboard.by_type"))
                    .font(.headline)
                Spacer()
                Text("\\(workspaceStore.operationLog.count)")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(loc("dashboard.total_ops"))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            Chart(operationCounts, id: \.0) { type, count in
                BarMark(x: .value("Type", type), y: .value("Count", count))
                    .foregroundStyle(Color.skyPrimary.gradient)
            }
            .frame(height: 160)
            .chartXAxis {
                AxisMarks { AxisValueLabel().font(.caption2) }
            }
        }
        .padding()
    }

    private var topModeratedCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "person.2.fill")
                    .font(.title2)
                    .foregroundStyle(Color.skyPrimary)
                Text(loc("dashboard.top_moderated"))
                    .font(.headline)
                Spacer()
            }
            let top = topModeratedAccounts()
            if top.isEmpty {
                Spacer()
                Text(loc("dashboard.no_data_yet"))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                Spacer()
            } else {
                ForEach(top.prefix(8), id: \.0) { handle, count in
                    HStack {
                        Text(handle)
                            .font(.subheadline.monospaced())
                            .lineLimit(1)
                        Spacer()
                        Text("\\(count)x")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Divider()
                }
            }
        }
        .padding()
    }

    private var recentActivityCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.title2)
                    .foregroundStyle(Color.skyPrimary)
                Text(loc("dashboard.recent"))
                    .font(.headline)
                Spacer()
            }
            ForEach(workspaceStore.operationLog.prefix(10)) { entry in
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.title)
                            .font(.subheadline.weight(.semibold))
                        Text(entry.summary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    Spacer()
                    Text(entry.createdAt, style: .date)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .padding(.vertical, 4)
                if entry.id != workspaceStore.operationLog.prefix(10).last?.id {
                    Divider()
                }
            }
        }
        .padding()
    }

    // MARK: - Computed Properties

    private var operationCounts: [(String, Int)] {
        let grouped = Dictionary(grouping: workspaceStore.operationLog, by: \.title)
        return grouped.map { ($0.key, $0.value.count) }.sorted { $0.1 > $1.1 }
    }

    private func topModeratedAccounts() -> [(String, Int)] {
        var counts: [String: Int] = [:]
        for entry in workspaceStore.operationLog {
            for handle in entry.succeededHandles {
                counts[handle, default: 0] += 1
            }
        }
        return counts.sorted { $0.value > $1.value }
    }
}

#Preview {
    NavigationStack {
        DashboardView()
            .environmentObject(AccountStore(preview: true))
            .environmentObject(ModerationWorkspaceStore(preview: true))
    }
}
