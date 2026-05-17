import SwiftUI

extension ListsView {
    /// Groups all sheet-presentation and navigation-destination state for ListsView
    /// into a single struct, replacing ten individual @State properties.
    struct PresentationState {
        var isShowingAccountPicker = false
        var isShowingCreateList = false
        var createListKind: BlueskyList.Kind = .moderation
        var showProfile = false
        var showFollowers = false
        var showFollowing = false
        var showBlocking = false
        var showBlockedBy = false
        var isShowingBulkLookup = false
        var isShowingAccountManagement = false
        var showMentionsSearch = false
        var showCustomSearch = false
    }
}
