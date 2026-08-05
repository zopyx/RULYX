import SwiftUI

struct iPadNotificationsView: View {
    @EnvironmentObject private var accountStore: AccountStore
    @EnvironmentObject private var container: BlueskyServiceContainerWrapper
    @EnvironmentObject private var localizationManager: LocalizationManager

    var body: some View {
        NotificationTab()
            .environmentObject(accountStore)
            .environmentObject(localizationManager)
    }
}
