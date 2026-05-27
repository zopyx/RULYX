import Charts
import SwiftUI

/// Dashboard view showing moderation activity stats — operations by type,
/// recent operation log, and top moderated accounts.
struct DashboardView: View {
    @EnvironmentObject private var accountStore: AccountStore
    @EnvironmentObject private var workspaceStore: ModerationWorkspaceStore
    @EnvironmentObject private var localizationManager: LocalizationManager

    // MARK: - Body

    var body: some View {
        List {
            Section {
                LabeledContent("dashboard.accounts", value: "\(accountStore.accounts.count)")
                LabeledContent("dashboard.total_ops", value: "\(workspaceStore.operationLog.count)")
            } header: {
                Text("dashboard.overview")
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
                    Text("dashboard.by_type")
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
                    Text("dashboard.recent")
                }

                Section {
                    let top = topModeratedAccounts()
                    if top.isEmpty {
                        Text("dashboard.no_data_yet").foregroundStyle(.secondary)
                    } else {
                        ForEach(top.prefix(10), id: \.0) { handle, count in
                            HStack {
                                Text(handle).font(.subheadline.monospaced())
                                Spacer()
                                Text("\(count)x").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                } header: {
                    Text("dashboard.top_moderated")
                }
            } else {
                ContentUnavailableView("dashboard.no_data", systemImage: "chart.bar", description: Text("dashboard.no_data_desc"))
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("dashboard.title")
    }

    // MARK: - Computed properties

    /// Aggregated operation counts keyed by title, sorted descending.
    private var operationCounts: [(String, Int)] {
        let grouped = Dictionary(grouping: workspaceStore.operationLog, by: \.title)
        return grouped.map { ($0.key, $0.value.count) }.sorted { $0.1 > $1.1 }
    }

    /// Returns the most-frequently moderated handles, sorted by count descending.
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
