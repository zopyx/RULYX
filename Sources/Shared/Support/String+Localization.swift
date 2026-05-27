import Foundation

// MARK: - Localization String Helpers

extension String {
    /// Convenience accessor for localized strings with optional `{key}` replacements.
    @MainActor
    static func localized(_ key: String, replacements: [String: String] = [:]) -> String {
        LocalizationManager.shared.localized(key).applyingLocalizationReplacements(replacements)
    }

    /// Replace `{key}` placeholders with the corresponding values.
    @MainActor
    func applyingLocalizationReplacements(_ replacements: [String: String]) -> String {
        replacements.reduce(self) { partialResult, replacement in
            partialResult.replacingOccurrences(of: "{\(replacement.key)}", with: replacement.value)
        }
    }
}
