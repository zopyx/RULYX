import SwiftUI

extension ListDetailView {
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

        var body: some View {
            Group {}
        }
    }
}
