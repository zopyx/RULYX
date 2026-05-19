@testable import RULYX
import XCTest

final class LocalizationCompletenessTests: XCTestCase {
    private var localizationsDir: URL {
        URL(fileURLWithPath: #file)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/Shared/Localizations")
    }

    private var sourcesDir: URL {
        URL(fileURLWithPath: #file)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources")
    }

    private var xcstringsURL: URL {
        localizationsDir.appendingPathComponent("Localizable.xcstrings")
    }

    private let supportedLanguages = ["en", "de", "fr", "it", "ja", "zh", "es", "pt", "ko", "ru", "ar", "nl", "pl", "tr", "th", "vi"]

    private func loadJSON(_ filename: String) throws -> [String: String] {
        let url = localizationsDir.appendingPathComponent(filename)
        let data = try Data(contentsOf: url)
        return try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: String])
    }

    private func placeholders(in value: String) -> Set<String> {
        let pattern = #"\{[A-Za-z0-9_]+\}"#
        let regex = try! NSRegularExpression(pattern: pattern)
        let range = NSRange(value.startIndex..., in: value)
        return Set(regex.matches(in: value, range: range).compactMap {
            Range($0.range, in: value).map { String(value[$0]) }
        })
    }

    private func loadXCStrings() throws -> [String: Any] {
        let data = try Data(contentsOf: xcstringsURL)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func xcstringsValue(_ strings: [String: Any], key: String, language: String) -> String? {
        let entries = strings["strings"] as? [String: Any]
        let entry = entries?[key] as? [String: Any]
        let localizations = entry?["localizations"] as? [String: Any]
        let localization = localizations?[language] as? [String: Any]
        let stringUnit = localization?["stringUnit"] as? [String: Any]
        return stringUnit?["value"] as? String
    }

    func testEnglishValuesAreNonEmpty() throws {
        let en = try loadJSON("en.json")
        let empty = en.filter { $0.value.trimmingCharacters(in: .whitespaces).isEmpty }
        XCTAssertTrue(empty.isEmpty, "\(empty.count) empty English translation(s): \(empty.keys.sorted())")
    }

    func testEnglishKeysAreNotPlaceholders() throws {
        let en = try loadJSON("en.json")
        let placeholders = en.filter { $0.key == $0.value.trimmingCharacters(in: .whitespaces) }
        XCTAssertTrue(placeholders.isEmpty, "\(placeholders.count) key(s) where value equals key: \(placeholders.keys.sorted())")
    }

    func testAllLanguagesHaveSameKeysAsEnglish() throws {
        let en = try loadJSON("en.json")
        let enKeys = Set(en.keys)
        var failures: [String: [String]] = [:]

        for lang in supportedLanguages where lang != "en" {
            let dict = try loadJSON("\(lang).json")
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
        let en = try loadJSON("en.json")
        XCTAssertGreaterThan(en.count, 900, "en.json has too few keys")
    }

    func testAllLanguageFilesAreLoadable() throws {
        var failures: [String] = []
        for lang in supportedLanguages {
            do {
                let dict = try loadJSON("\(lang).json")
                XCTAssertGreaterThan(dict.count, 500)
            } catch {
                failures.append("\(lang).json: \(error.localizedDescription)")
            }
        }
        XCTAssertTrue(failures.isEmpty, "Failed to load: \(failures.joined(separator: ", "))")
    }

    func testAllLanguagesPreserveEnglishPlaceholderContracts() throws {
        let english = try loadJSON("en.json")
        var failures: [String] = []

        for lang in supportedLanguages where lang != "en" {
            let localized = try loadJSON("\(lang).json")
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
        let xcstrings = try loadXCStrings()
        let english = try loadJSON("en.json")
        var bundles: [String: [String: String]] = ["en": english]

        for lang in supportedLanguages where lang != "en" {
            bundles[lang] = try loadJSON("\(lang).json")
        }

        var failures: [String] = []
        for key in english.keys.sorted() {
            for lang in supportedLanguages {
                let expected = bundles[lang]?[key]
                let actual = xcstringsValue(xcstrings, key: key, language: lang)
                if actual != expected {
                    failures.append("\(key)/\(lang): expected \(expected ?? "nil"), got \(actual ?? "nil")")
                }
            }
        }

        XCTAssertTrue(failures.isEmpty, "xcstrings drift detected:\n\(failures.joined(separator: "\n"))")
    }

    func testSwiftSourcesDoNotInterpolateDirectlyOnLocalizationKeys() throws {
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
}
