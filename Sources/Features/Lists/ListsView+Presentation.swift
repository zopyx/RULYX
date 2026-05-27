import SwiftUI

// MARK: - Presentation state

extension ListsView {
    /// Groups all sheet-presentation and navigation-destination state for ListsView
    /// into a single struct, replacing ten individual @State properties.
    struct PresentationState {
        var isShowingAccountPicker = false // Account switcher sheet
        var isShowingCreateList = false // Create-list metadata sheet
        var createListKind: BlueskyList.Kind = .moderation // Kind being created
        var showProfile = false // Navigation to own BlueskyProfileView
        var showFollowers = false // Navigation to followers RelationshipsView
        var showFollowing = false // Navigation to following RelationshipsView
        var showBlocking = false // Navigation to blocking RelationshipsView
        var showBlockedBy = false // Navigation to blocked-by RelationshipsView
        var isShowingBulkLookup = false // Bulk profile lookup sheet
        var isShowingAccountManagement = false // Account management sheet
        var showMentionsSearch = false // Navigation to MentionsSearchView
        var showCustomSearch = false // Navigation to CustomSearchView
        var showDirectReplies = false // Navigation to DirectRepliesView
        var isShowingCreateInternalList = false // Internal list creation sheet
    }
}
