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
    var allBundles: [String: [String: String]] = [:]

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

    var locale: Locale {
        Locale(identifier: currentLanguage)
    }

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

    func localized(_ key: String) -> String {
        bundle[key] ?? allBundles["en"]?[key] ?? key
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

enum PluralCategory: String, CaseIterable {
    case zero, one, two, few, many, other
}

enum PluralRules {
    static func category(for count: Int, language: String) -> PluralCategory {
        switch language {
        case "en", "de", "it", "nl", "pt", "es", "tr":
            return count == 1 ? .one : .other
        case "fr":
            return (count == 0 || count == 1) ? .one : .other
        case "ru":
            if count % 10 == 1 && count % 100 != 11 { return .one }
            if count % 10 >= 2 && count % 10 <= 4 && (count % 100 < 10 || count % 100 >= 20) { return .few }
            return .many
        case "ar":
            if count == 0 { return .zero }
            if count == 1 { return .one }
            if count == 2 { return .two }
            if count % 100 >= 3 && count % 100 <= 10 { return .few }
            if count % 100 >= 11 { return .many }
            return .other
        case "pl":
            if count == 1 { return .one }
            if count % 10 >= 2 && count % 10 <= 4 && (count % 100 < 10 || count % 100 >= 20) { return .few }
            return .many
        case "ja", "zh", "ko", "th", "vi":
            return .other
        default:
            return count == 1 ? .one : .other
        }
    }

    static func lookupOrder(for category: PluralCategory) -> [PluralCategory] {
        switch category {
        case .zero: return [.zero, .other]
        case .one: return [.one, .other]
        case .two: return [.two, .other]
        case .few: return [.few, .other]
        case .many: return [.many, .other]
        case .other: return [.other]
        }
    }
}

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
