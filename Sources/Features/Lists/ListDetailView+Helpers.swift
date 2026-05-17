import SwiftUI

extension ListDetailView {
    var snapshotHistory: [ListMembershipSnapshot] {
        workspaceStore.snapshotHistory(for: currentList.id)
    }

    var selectedSnapshotComparison: ListMembershipSnapshotSummary? {
        guard let newerID = comparisonState.selectedNewerSnapshotID,
              let olderID = comparisonState.selectedOlderSnapshotID,
              newerID != olderID
        else {
            return nil
        }

        return workspaceStore.compareSnapshots(
            listID: currentList.id,
            newerSnapshotID: newerID,
            olderSnapshotID: olderID
        )
    }

    var comparisonList: BlueskyList? {
        viewModel.availableLists.first { $0.id == comparisonState.selectedComparisonListID }
    }

    var exportFileURL: URL? {
        if let cached = exportState.cachedExportFileURL { return cached }
        let url = fileURL(named: exportFileName, rows: ["handle,did,display_name"] + viewModel.exportRows())
        exportState.cachedExportFileURL = url
        return url
    }

    var diffExportFileURL: URL? {
        if let cached = exportState.cachedDiffExportFileURL { return cached }
        guard viewModel.comparisonReport != nil else { return nil }
        let url = fileURL(
            named: "\(exportFileName.replacingOccurrences(of: "-members", with: ""))-diff.csv",
            rows: ["bucket,handle,did,display_name"] + viewModel.exportDiffRows()
        )
        exportState.cachedDiffExportFileURL = url
        return url
    }

    var exportFileName: String {
        let sanitizedName = currentList.name
            .lowercased()
            .replacingOccurrences(of: " ", with: "-")
        return "\(sanitizedName)-members.csv"
    }

    func fileURL(named fileName: String, rows: [String]) -> URL? {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(fileName)
        let content = rows.joined(separator: "\n")

        do {
            try content.write(to: fileURL, atomically: true, encoding: .utf8)
            return fileURL
        } catch {
            return nil
        }
    }

    func reloadListContext(account: AppAccount, appPassword: String) async {
        async let membersTask: Void = viewModel.loadMembers(
            for: currentList,
            account: account,
            appPassword: appPassword,
            using: blueskyClient
        )
        async let listsTask: Void = viewModel.loadAvailableLists(
            excluding: currentList,
            account: account,
            appPassword: appPassword,
            using: blueskyClient
        )

        _ = await (membersTask, listsTask)

        if comparisonState.selectedComparisonListID.isEmpty {
            comparisonState.selectedComparisonListID = viewModel.availableLists.first?.id ?? ""
        }
        syncSnapshot()
        syncSnapshotSelection()
    }

    func syncSnapshot() {
        comparisonState.snapshotSummary = workspaceStore.captureSnapshot(for: currentList, members: viewModel.members)
        syncSnapshotSelection()
    }

    func syncSnapshotSelection() {
        let history = snapshotHistory
        if comparisonState.selectedNewerSnapshotID == nil {
            comparisonState.selectedNewerSnapshotID = history.first?.id
        }

        if comparisonState.selectedOlderSnapshotID == nil {
            comparisonState.selectedOlderSnapshotID = history.dropFirst().first?.id ?? history.first?.id
        }
    }

    func comparisonSummary(report: ListComparisonReport) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(loc("list.compare.compared_with").replacingOccurrences(of: "{name}", with: report.otherList.name))
                .font(.subheadline.weight(.semibold))

            Text(loc("list.compare.overlap_count").replacingOccurrences(of: "{count}", with: "\(report.overlap.count)"))
            Text(loc("list.compare.only_current").replacingOccurrences(of: "{name}", with: currentList.name).replacingOccurrences(of: "{count}", with: "\(report.onlyInCurrent.count)"))
            Text(loc("list.compare.only_other").replacingOccurrences(of: "{name}", with: report.otherList.name).replacingOccurrences(of: "{count}", with: "\(report.onlyInOther.count)"))
        }
    }

    func snapshotSummaryView(_ summary: ListMembershipSnapshotSummary) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if summary.hasChanges {
                if !summary.addedMembers.isEmpty {
                    Text(verbatim: loc("list.snapshot.added").replacingOccurrences(of: "{handles}", with: summary.addedMembers.map(\.handle).joined(separator: ", ")))
                }

                if !summary.removedMembers.isEmpty {
                    Text(verbatim: loc("list.snapshot.removed").replacingOccurrences(of: "{handles}", with: summary.removedMembers.map(\.handle).joined(separator: ", ")))
                }
            } else {
                Text(verbatim: loc("list.snapshot.no_changes"))
                    .foregroundStyle(.secondary)
            }
        }
        .font(.caption)
    }

    func handleImportedFile(_ result: Result<URL, Error>) {
        switch result {
        case let .success(url):
            do {
                let content = try String(contentsOf: url, encoding: .utf8)
                if let account = accountStore.activeAccount,
                   let appPassword = accountStore.appPassword(for: account)
                {
                    Task {
                        await viewModel.prepareImportPreview(
                            from: content,
                            sourceDescription: url.lastPathComponent,
                            account: account,
                            appPassword: appPassword,
                            using: blueskyClient
                        )
                    }
                }
            } catch {
                viewModel.errorMessage = error.localizedDescription
            }
        case let .failure(error):
            viewModel.errorMessage = error.localizedDescription
        }
    }

    func bulkActionMessage(for result: ListBulkActionResult) -> String {
        if result.failures.isEmpty {
            return result.summaryText
        }

        let failureDetails = result.failures
            .map { "\($0.actor.handle): \($0.message)" }
            .joined(separator: "\n")

        return "\(result.summaryText)\n\n\(loc("activity.failed_format").replacingOccurrences(of: "{handles}", with: failureDetails))"
    }
}
