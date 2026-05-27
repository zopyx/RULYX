import SwiftUI

// MARK: - Localized Text

/// Convenience initializers that look up localized strings at init time.
@MainActor
extension Text {
    /// Creates a `Text` view from a localization key (no `LocalizedStringKey` interpolation).
    init(loc key: String) {
        self.init(verbatim: LocalizationManager.shared.localized(key))
    }
}

// MARK: - Localized View Modifiers

/// View modifiers that apply localized strings for navigation and accessibility.
@MainActor
extension View {
    /// Set navigation title from a localization key.
    func navigationTitle(loc key: String) -> some View {
        navigationTitle(LocalizationManager.shared.localized(key))
    }

    /// Set accessibility label from a localization key.
    func accessibilityLabel(loc key: String) -> some View {
        accessibilityLabel(LocalizationManager.shared.localized(key))
    }

    /// Set accessibility hint from a localization key.
    func accessibilityHint(loc key: String) -> some View {
        accessibilityHint(LocalizationManager.shared.localized(key))
    }
}
