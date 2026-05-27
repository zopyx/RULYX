import SwiftUI

struct iPadNotificationsView: View {
    @EnvironmentObject private var accountStore: AccountStore
    @EnvironmentObject private var blueskyClient: LiveBlueskyClient
    @EnvironmentObject private var localizationManager: LocalizationManager

    var body: some View {
        NotificationTab()
            .environmentObject(accountStore)
            .environmentObject(blueskyClient)
            .environmentObject(localizationManager)
    }
}
