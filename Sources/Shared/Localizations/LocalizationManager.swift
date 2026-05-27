import SwiftUI

/// Global localization manager — singleton that loads all 16 language JSON bundles
/// and provides key-based lookups with fallback chain: selected → device → English → raw key.
@MainActor
final class LocalizationManager: ObservableObject {
    static let shared = LocalizationManager()

    /// Currently active language code (e.g. "en", "de", "ja").
    /// Setting this persists to UserDefaults and reloads the bundle.
    @Published var currentLanguage: String {
        didSet {
            UserDefaults.standard.set(currentLanguage, forKey: "selectedLanguage")
            loadCurrentBundle()
        }
    }

    /// Active language's key→value dictionary.
    private var bundle: [String: String] = [:]
    /// All loaded language bundles (code → key→value).
    var allBundles: [String: [String: String]] = [:]

    /// Supported language codes with their display names.
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

    /// Locale derived from the current language.
    var locale: Locale {
        Locale(identifier: currentLanguage)
    }

    /// Layout direction — RTL for Arabic, LTR for all others.
    var layoutDirection: LayoutDirection {
        currentLanguage == "ar" ? .rightToLeft : .leftToRight
    }

    private init() {
        let saved = UserDefaults.standard.string(forKey: "selectedLanguage")
        let preferred = Locale.current.language.languageCode?.identifier
        let allCodes = supportedLanguages.map(\.code)
        currentLanguage = saved ?? (preferred != nil && allCodes.contains(preferred!) ? preferred! : "en")
        loadAll()
        loadCurrentBundle()
    }

    /// Look up `key` in the active bundle; fall back to English, then raw key.
    func localized(_ key: String) -> String {
        bundle[key] ?? allBundles["en"]?[key] ?? key
    }

    /// Load all 16 JSON bundles from the main bundle into memory.
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

    /// Swap the active bundle to match `currentLanguage` and notify observers.
    private func loadCurrentBundle() {
        bundle = allBundles[currentLanguage] ?? allBundles["en"] ?? [:]
        objectWillChange.send()
    }
}

/// Convenience global function for quick localization lookups.
@MainActor
func loc(_ key: String) -> String {
    LocalizationManager.shared.localized(key)
}

/// Returns a human-readable localized string for a known label value (e.g. "bot", "spam").
/// Falls back to the raw value for unknown labels.
@MainActor
func localizedLabel(_ val: String) -> String {
    let key = "label.\(val)"
    let localized = LocalizationManager.shared.localized(key)
    if localized != key {
        return localized
    }
    return val
}

// MARK: - CLDR Plural Rules

/// Plural categories per CLDR spec.
enum PluralCategory: String, CaseIterable {
    case zero, one, two, few, many, other
}

/// Resolves plural categories for supported languages using CLDR cardinal rules.
enum PluralRules {
    /// Determine the appropriate plural category for `count` in the given `language`.
    static func category(for count: Int, language: String) -> PluralCategory {
        switch language {
        case "en", "de", "it", "nl", "pt", "es", "tr":
            return count == 1 ? .one : .other
        case "fr":
            return (count == 0 || count == 1) ? .one : .other
        case "ru":
            if count % 10 == 1, count % 100 != 11 { return .one }
            if count % 10 >= 2, count % 10 <= 4, count % 100 < 10 || count % 100 >= 20 { return .few }
            return .many
        case "ar":
            if count == 0 { return .zero }
            if count == 1 { return .one }
            if count == 2 { return .two }
            if count % 100 >= 3, count % 100 <= 10 { return .few }
            if count % 100 >= 11 { return .many }
            return .other
        case "pl":
            if count == 1 { return .one }
            if count % 10 >= 2, count % 10 <= 4, count % 100 < 10 || count % 100 >= 20 { return .few }
            return .many
        case "ja", "zh", "ko", "th", "vi":
            return .other
        default:
            return count == 1 ? .one : .other
        }
    }

    /// Preferred lookup order for plurals: the matching category first, then `.other`.
    static func lookupOrder(for category: PluralCategory) -> [PluralCategory] {
        switch category {
        case .zero: [.zero, .other]
        case .one: [.one, .other]
        case .two: [.two, .other]
        case .few: [.few, .other]
        case .many: [.many, .other]
        case .other: [.other]
        }
    }
}

/// Look up a pluralized localization key (e.g. `"item_count_one"` / `"item_count_other"`)
/// based on the count and current language.
@MainActor
func locPlural(_ keyPrefix: String, count: Int) -> String {
    let language = LocalizationManager.shared.currentLanguage
    let category = PluralRules.category(for: count, language: language)
    let lookupOrder = PluralRules.lookupOrder(for: category)
    for cat in lookupOrder {
        let key = "\(keyPrefix)_\(cat.rawValue)"
        let result = LocalizationManager.shared.localized(key)
        if result != key { return result }
    }
    return keyPrefix
}
