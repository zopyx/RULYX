import SwiftUI

struct LText: View {
    @EnvironmentObject private var localizationManager: LocalizationManager
    let key: String

    var body: some View {
        Text(localizationManager.localized(key))
    }
}

extension View {
    func localizedString(_ key: String) -> String {
        LocalizationManager.shared.localized(key)
    }
}
