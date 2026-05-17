import Foundation

extension ListDetailView {
    /// Groups export-related state into a single struct.
    struct ExportState {
        var cachedExportFileURL: URL?
        var cachedDiffExportFileURL: URL?
    }

    /// Groups list-comparison and snapshot-related state into a single struct.
    struct ComparisonState {
        var selectedComparisonListID = ""
        var snapshotSummary: ListMembershipSnapshotSummary?
        var selectedNewerSnapshotID: UUID?
        var selectedOlderSnapshotID: UUID?
    }

    /// Groups sheet-presentation state for import/edit operations into a single struct.
    struct ImportState {
        var isShowingEditSheet = false
        var isShowingImportSheet = false
        var isShowingImportFilePicker = false
    }
}
