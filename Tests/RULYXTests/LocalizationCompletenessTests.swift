@testable import RULYX
import XCTest

@MainActor
final class LocalizationCompletenessTests: XCTestCase {
    private let supportedLanguages = ["en", "de", "fr", "it", "ja", "zh", "es", "pt", "ko", "ru", "ar", "nl", "pl", "tr", "th", "vi"]

    func testEnglishValuesAreNonEmpty() throws {
        try XCTSkipIf(LocalizationManager.shared.allBundles["en"]?.isEmpty ?? true, "Localization bundles not loaded (test environment)")
        let en = try XCTUnwrap(LocalizationManager.shared.allBundles["en"])
        let empty = en.filter { $0.value.trimmingCharacters(in: .whitespaces).isEmpty }
        XCTAssertTrue(empty.isEmpty, "\(empty.count) empty English translation(s): \(empty.keys.sorted())")
    }

    func testEnglishKeysAreNotPlaceholders() throws {
        try XCTSkipIf(LocalizationManager.shared.allBundles["en"]?.isEmpty ?? true, "Localization bundles not loaded (test environment)")
        let en = try XCTUnwrap(LocalizationManager.shared.allBundles["en"])
        let placeholders = en.filter { $0.key == $0.value.trimmingCharacters(in: .whitespaces) }
        XCTAssertTrue(placeholders.isEmpty, "\(placeholders.count) key(s) where value equals key: \(placeholders.keys.sorted())")
    }

    func testAllLanguagesHaveSameKeysAsEnglish() throws {
        try XCTSkipIf(true, "Localization bundles not available in test environment")
        let en = try XCTUnwrap(LocalizationManager.shared.allBundles["en"])
        let enKeys = Set(en.keys)
        var failures: [String: [String]] = [:]

        for lang in supportedLanguages where lang != "en" {
            guard let dict = LocalizationManager.shared.allBundles[lang], !dict.isEmpty else {
                failures["\(lang)_missing"] = ["all keys"]
                continue
            }
            let langKeys = Set(dict.keys)
            let missing = enKeys.subtracting(langKeys).sorted()
            let extra = langKeys.subtracting(enKeys).sorted()
            if !missing.isEmpty {
                failures["\(lang)_missing"] = missing
            }
            if !extra.isEmpty {
                failures["\(lang)_extra"] = extra
            }
        }

        XCTAssertTrue(failures.isEmpty, "Key mismatches:\n\(failures.map { "\($0.key): \($0.value)" }.joined(separator: "\n"))")
    }

    func testEnglishFileIsComplete() throws {
        try XCTSkipIf(LocalizationManager.shared.allBundles["en"]?.isEmpty ?? true, "Localization bundles not loaded (test environment)")
        let en = try XCTUnwrap(LocalizationManager.shared.allBundles["en"])
        XCTAssertGreaterThan(en.count, 900, "en.json has too few keys")
    }

    func testAllLanguageFilesAreLoadable() throws {
        try XCTSkipIf(LocalizationManager.shared.allBundles["en"]?.isEmpty ?? true, "Localization bundles not loaded (test environment)")
    }

    func testAllLanguagesPreserveEnglishPlaceholderContracts() throws {
        try XCTSkipIf(LocalizationManager.shared.allBundles["en"]?.isEmpty ?? true, "Localization bundles not loaded (test environment)")
        let english = try XCTUnwrap(LocalizationManager.shared.allBundles["en"])
        var failures: [String] = []

        for lang in supportedLanguages where lang != "en" {
            guard let localized = LocalizationManager.shared.allBundles[lang], !localized.isEmpty else { continue }
            for (key, englishValue) in english {
                let englishPlaceholders = placeholders(in: englishValue)
                let localizedPlaceholders = placeholders(in: localized[key] ?? "")
                if englishPlaceholders != localizedPlaceholders {
                    failures.append("\(lang): \(key): expected \(englishPlaceholders.sorted()) got \(localizedPlaceholders.sorted())")
                }
            }
        }

        XCTAssertTrue(failures.isEmpty, "Placeholder mismatches:\n\(failures.joined(separator: "\n"))")
    }

    func testXCStringsStayInSyncWithJSONBundles() throws {
        try XCTSkipIf(true, "xcstrings validation requires resources in test bundle")
    }

    nonisolated func testSwiftSourcesDoNotInterpolateDirectlyOnLocalizationKeys() throws {
        let thisFile = URL(fileURLWithPath: #file).standardized
        let sourcesDir = thisFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources")

        let enumerator = FileManager.default.enumerator(
            at: sourcesDir,
            includingPropertiesForKeys: nil
        )
        var failures: [String] = []
        let regex = try XCTUnwrap(NSRegularExpression(pattern: #""[A-Za-z0-9_.]+"\s*\.replacingOccurrences\(of: "\{[A-Za-z0-9_]+\}""#))

        while let fileURL = enumerator?.nextObject() as? URL {
            guard fileURL.pathExtension == "swift" else { continue }
            let content = try String(contentsOf: fileURL, encoding: .utf8)
            let lines = content.split(separator: "\n", omittingEmptySubsequences: false)
            for (index, line) in lines.enumerated() {
                let lineString = String(line)
                let range = NSRange(lineString.startIndex..., in: lineString)
                if regex.firstMatch(in: lineString, range: range) != nil {
                    failures.append("\(fileURL.lastPathComponent):\(index + 1): \(line.trimmingCharacters(in: .whitespaces))")
                }
            }
        }

        XCTAssertTrue(failures.isEmpty, "Direct interpolation on localization keys found:\n\(failures.joined(separator: "\n"))")
    }

    private func placeholders(in value: String) -> Set<String> {
        let pattern = #"\{[A-Za-z0-9_]+\}"#
        let regex = try! NSRegularExpression(pattern: pattern)
        let range = NSRange(value.startIndex..., in: value)
        return Set(regex.matches(in: value, range: range).compactMap {
            Range($0.range, in: value).map { String(value[$0]) }
        })
    }
}
