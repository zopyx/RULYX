import SwiftUI

extension ListDetailView {
    // MARK: - ListSnapshotSection

    /// Placeholder section for comparing list membership snapshots
    /// (currently not implemented — renders an empty Group).
    struct ListSnapshotSection: View {
        @ObservedObject var viewModel: ListDetailViewModel
        let snapshotSummary: ListMembershipSnapshotSummary?
        @Binding var selectedNewerSnapshotID: UUID?
        @Binding var selectedOlderSnapshotID: UUID?
        let snapshotHistory: [ListMembershipSnapshot]
        let selectedSnapshotComparison: ListMembershipSnapshotSummary?

        @EnvironmentObject var accountStore: AccountStore
        @EnvironmentObject var blueskyClient: LiveBlueskyClient
        @EnvironmentObject var workspaceStore: ModerationWorkspaceStore

        // MARK: - Body

        var body: some View {
            Group {}
        }
    }
}
