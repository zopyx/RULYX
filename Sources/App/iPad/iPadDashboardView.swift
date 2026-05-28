import Charts
import SwiftUI

struct iPadDashboardView: View {
    @EnvironmentObject private var accountStore: AccountStore
    @EnvironmentObject private var workspaceStore: ModerationWorkspaceStore
    @EnvironmentObject private var localizationManager: LocalizationManager

    private let columns = [
        GridItem(.adaptive(minimum: 300, maximum: 450), spacing: 16),
    ]

    var body: some View {
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

    private var accountsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "person.circle.fill")
                    .font(.title2)
                    .foregroundStyle(Color.skyPrimary)
                Text(loc("dashboard.accounts"))
                    .font(.headline)
                Spacer()
                Text("\(accountStore.accounts.count)")
                    .font(.largeTitle.weight(.bold))
                    .foregroundStyle(Color.skyPrimary)
            }
            if let active = accountStore.activeAccount {
                HStack {
                    Text(active.displayName ?? active.handle)
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
                Text("\(workspaceStore.operationLog.count)")
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
                        Text("\(count)x")
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
