import SwiftUI

@MainActor
extension Text {
    init(loc key: String) {
        self.init(verbatim: LocalizationManager.shared.localized(key))
    }
}

@MainActor
extension View {
    func navigationTitle(loc key: String) -> some View {
        navigationTitle(LocalizationManager.shared.localized(key))
    }

    func accessibilityLabel(loc key: String) -> some View {
        accessibilityLabel(LocalizationManager.shared.localized(key))
    }

    func accessibilityHint(loc key: String) -> some View {
        accessibilityHint(LocalizationManager.shared.localized(key))
    }
}
