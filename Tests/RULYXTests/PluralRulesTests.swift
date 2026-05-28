@testable import RULYX
import XCTest

final class PluralRulesTests: XCTestCase {
    func test_english_one_and_other() {
        XCTAssertEqual(PluralRules.category(for: 1, language: "en"), .one)
        XCTAssertEqual(PluralRules.category(for: 0, language: "en"), .other)
        XCTAssertEqual(PluralRules.category(for: 2, language: "en"), .other)
        XCTAssertEqual(PluralRules.category(for: 21, language: "en"), .other)
    }

    func test_russian_one_few_many() {
        XCTAssertEqual(PluralRules.category(for: 1, language: "ru"), .one)
        XCTAssertEqual(PluralRules.category(for: 21, language: "ru"), .one)
        XCTAssertEqual(PluralRules.category(for: 11, language: "ru"), .many)
        XCTAssertEqual(PluralRules.category(for: 2, language: "ru"), .few)
        XCTAssertEqual(PluralRules.category(for: 4, language: "ru"), .few)
        XCTAssertEqual(PluralRules.category(for: 22, language: "ru"), .few)
        XCTAssertEqual(PluralRules.category(for: 12, language: "ru"), .many)
        XCTAssertEqual(PluralRules.category(for: 5, language: "ru"), .many)
        XCTAssertEqual(PluralRules.category(for: 0, language: "ru"), .many)
    }

    func test_polish_one_few_many() {
        XCTAssertEqual(PluralRules.category(for: 1, language: "pl"), .one)
        XCTAssertEqual(PluralRules.category(for: 2, language: "pl"), .few)
        XCTAssertEqual(PluralRules.category(for: 22, language: "pl"), .few)
        XCTAssertEqual(PluralRules.category(for: 12, language: "pl"), .many)
        XCTAssertEqual(PluralRules.category(for: 5, language: "pl"), .many)
        XCTAssertEqual(PluralRules.category(for: 21, language: "pl"), .many)
        XCTAssertEqual(PluralRules.category(for: 0, language: "pl"), .many)
    }

    func test_arabic_full_set() {
        XCTAssertEqual(PluralRules.category(for: 0, language: "ar"), .zero)
        XCTAssertEqual(PluralRules.category(for: 1, language: "ar"), .one)
        XCTAssertEqual(PluralRules.category(for: 2, language: "ar"), .two)
        XCTAssertEqual(PluralRules.category(for: 3, language: "ar"), .few)
        XCTAssertEqual(PluralRules.category(for: 10, language: "ar"), .few)
        XCTAssertEqual(PluralRules.category(for: 11, language: "ar"), .many)
        XCTAssertEqual(PluralRules.category(for: 99, language: "ar"), .many)
        XCTAssertEqual(PluralRules.category(for: 100, language: "ar"), .other)
    }

    func test_other_only_languages() {
        for lang in ["ja", "ko", "zh", "th", "vi"] {
            XCTAssertEqual(PluralRules.category(for: 1, language: lang), .other)
            XCTAssertEqual(PluralRules.category(for: 5, language: lang), .other)
            XCTAssertEqual(PluralRules.category(for: 0, language: lang), .other)
        }
    }

    func test_lookup_order_falls_back_to_other() {
        XCTAssertEqual(PluralRules.lookupOrder(for: .zero), [.zero, .other])
        XCTAssertEqual(PluralRules.lookupOrder(for: .few), [.few, .other])
        XCTAssertEqual(PluralRules.lookupOrder(for: .many), [.many, .other])
        XCTAssertEqual(PluralRules.lookupOrder(for: .other), [.other])
    }
}
