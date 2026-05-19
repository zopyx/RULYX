import SwiftUI

struct ReportGeneratorView: View {
    @EnvironmentObject private var accountStore: AccountStore
    @EnvironmentObject private var workspaceStore: ModerationWorkspaceStore
    @EnvironmentObject private var localizationManager: LocalizationManager
    @State private var reportText = ""
    @State private var includeStats = true

    var body: some View {
        List {
            Section {
                Toggle(isOn: $includeStats) {
                    Text("report.include_stats")
                }
                .accessibilityHint("report.include_stats.hint")
            }

            if !reportText.isEmpty {
                Section {
                    Text(reportText).font(.caption.monospaced())
                } header: {
                    Text("report.preview")
                }

                Section {
                    ShareLink(item: reportText, subject: Text("report.subject")) {
                        Label {
                            Text("report.share")
                        } icon: {
                            Image(systemName: "arrow.down.doc")
                        }
                    }
                    .accessibilityHint("report.share.hint")
                }
            }

            Section {
                Button("report.generate") {
                    generateReport()
                }
                .accessibilityHint("report.generate.hint")
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("report.title")
    }

    private func generateReport() {
        var lines: [String] = []
        lines.append(String(localized: "report.doc_title"))
        lines.append(String(localized: "report.doc_generated").replacingOccurrences(of: "{date}", with: Date.now.formatted(date: .complete, time: .shortened)))
        lines.append("")

        let log = workspaceStore.operationLog
        if includeStats {
            let totalOps = log.count
            let totalSuccess = log.reduce(0) { $0 + $1.succeededHandles.count }
            let totalFailed = log.reduce(0) { $0 + $1.failedHandles.count }
            lines.append(String(localized: "report.doc_summary"))
            lines.append(String(localized: "report.doc_total_operations").replacingOccurrences(of: "{count}", with: "\(totalOps)"))
            lines.append(String(localized: "report.doc_accounts_actioned").replacingOccurrences(of: "{count}", with: "\(totalSuccess)"))
            lines.append(String(localized: "report.doc_total_failures").replacingOccurrences(of: "{count}", with: "\(totalFailed)"))
            lines.append("")

            let byType = Dictionary(grouping: log, by: \.title)
                .mapValues(\.count)
                .sorted { $0.value > $1.value }
            lines.append(String(localized: "report.doc_operations_by_type"))
            for (type, count) in byType {
                lines.append(String(localized: "report.doc_operation_line").replacingOccurrences(of: "{type}", with: type).replacingOccurrences(of: "{count}", with: "\(count)"))
            }
            lines.append("")
        }

        lines.append(String(localized: "report.doc_recent_activity"))
        for entry in log.prefix(10) {
            lines.append(String(localized: "report.doc_activity_line").replacingOccurrences(of: "{title}", with: entry.title).replacingOccurrences(of: "{summary}", with: entry.summary).replacingOccurrences(of: "{date}", with: entry.createdAt.formatted(date: .abbreviated, time: .shortened)))
        }

        reportText = lines.joined(separator: "\n")
    }
}

#Preview {
    NavigationStack { ReportGeneratorView().environmentObject(ModerationWorkspaceStore(preview: true)) }
}
