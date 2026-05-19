import Foundation

extension String {
    @MainActor
    static func localized(_ key: String, replacements: [String: String] = [:]) -> String {
        LocalizationManager.shared.localized(key).applyingLocalizationReplacements(replacements)
    }

    @MainActor
    func applyingLocalizationReplacements(_ replacements: [String: String]) -> String {
        replacements.reduce(self) { partialResult, replacement in
            partialResult.replacingOccurrences(of: "{\(replacement.key)}", with: replacement.value)
        }
    }
}
