import SwiftUI

/// Wraps MentionsSearchView for the iPad sidebar content column.
/// Since MentionsSearchView requires a specific actor (did, handle, displayName),
/// this wrapper shows an empty state prompting navigation to a profile first.
struct iPadMentionsSearchWrapper: View {
    @EnvironmentObject private var accountStore: AccountStore
    @EnvironmentObject private var localizationManager: LocalizationManager

    var body: some View {
        ContentUnavailableView(
            "iPad / Mentions Search",
            systemImage: "at",
            description: Text("Navigate to a profile first, then select Mentions Search from the context menu.")
        )
    }
}
