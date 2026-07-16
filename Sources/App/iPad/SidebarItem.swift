import Foundation

/// Navigation item identifiers for iPad keyboard shortcuts and command palette.
/// Mapped to tab navigation via `navigateToSidebarItem` in `RootView`.
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
}
