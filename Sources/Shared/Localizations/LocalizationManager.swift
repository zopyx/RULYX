import SwiftUI

@MainActor
final class LocalizationManager: ObservableObject {
    static let shared = LocalizationManager()

    @Published var currentLanguage: String {
        didSet {
            UserDefaults.standard.set(currentLanguage, forKey: "selectedLanguage")
            loadCurrentBundle()
        }
    }

    private var bundle: [String: String] = [:]
    private var allBundles: [String: [String: String]] = [:]

    let supportedLanguages: [(code: String, displayName: String)] = [
        ("en", "English"),
        ("de", "Deutsch"),
        ("fr", "Français"),
        ("it", "Italiano"),
        ("ja", "日本語"),
        ("zh", "中文"),
        ("es", "Español"),
        ("pt", "Português"),
        ("ko", "한국어"),
        ("ru", "Русский"),
        ("ar", "العربية"),
        ("nl", "Nederlands"),
        ("pl", "Polski"),
        ("tr", "Türkçe"),
        ("th", "ไทย"),
        ("vi", "Tiếng Việt"),
    ]

    private init() {
        let saved = UserDefaults.standard.string(forKey: "selectedLanguage")
        let preferred = Locale.current.language.languageCode?.identifier
        let allCodes = supportedLanguages.map(\.code)
        currentLanguage = saved ?? (preferred != nil && allCodes.contains(preferred!) ? preferred! : "en")
        loadAll()
        loadCurrentBundle()
    }

    func localized(_ key: String) -> String {
        bundle[key] ?? allBundles["en"]?[key] ?? key
    }

    func localizedPlural(_ key: String, count: Int) -> String {
        let language = currentLanguage
        let pluralKey: String = if language == "en" || language == "de" || language == "fr" || language == "it" {
            count == 1 ? "\(key)_one" : "\(key)_other"
        } else {
            // Default to English-style plural rules
            count == 1 ? "\(key)_one" : "\(key)_other"
        }
        let format = bundle[pluralKey] ?? allBundles["en"]?[pluralKey] ?? bundle[key] ?? allBundles["en"]?[key] ?? key
        return format.replacingOccurrences(of: "{count}", with: "\(count)")
    }

    private func loadAll() {
        let allCodes = supportedLanguages.map(\.code)
        for lang in allCodes {
            guard let url = Bundle.main.url(forResource: lang, withExtension: "json"),
                  let data = try? Data(contentsOf: url),
                  let dict = try? JSONDecoder().decode([String: String].self, from: data)
            else {
                allBundles[lang] = [:]
                continue
            }
            allBundles[lang] = dict
        }
    }

    private func loadCurrentBundle() {
        bundle = allBundles[currentLanguage] ?? allBundles["en"] ?? [:]
        objectWillChange.send()
    }
}

@MainActor
func loc(_ key: String) -> String {
    LocalizationManager.shared.localized(key)
}
