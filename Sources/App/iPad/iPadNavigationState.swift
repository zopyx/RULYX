import SwiftUI

enum SidebarItem: String, Hashable, CaseIterable {
    case allLists
    case templates
    case rules
    case dashboard
    case relationships
    case customSearch
    case mentionsSearch
    case bulkLookup
    case networkGraph
    case timeline
    case notifications
    case chat
    case settings
    case accounts
    case info

    var section: SidebarSection {
        switch self {
        case .allLists, .templates, .rules, .dashboard, .relationships:
            .moderation
        case .customSearch, .mentionsSearch, .bulkLookup, .networkGraph:
            .searchProfiles
        case .timeline, .notifications, .chat:
            .social
        case .settings, .accounts, .info:
            .system
        }
    }
}

enum SidebarSection: String, Hashable, CaseIterable {
    case moderation
    case searchProfiles
    case social
    case system
}

@MainActor
final class iPadNavigationState: ObservableObject {
    @Published var sidebarSelection: SidebarItem? = .allLists
    @Published var columnVisibility: NavigationSplitViewVisibility = .all
    @Published var selectedList: BlueskyList?
    @Published var selectedProfileDID: String?
}
