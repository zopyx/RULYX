@testable import RULYX
import XCTest

final class GIFServiceModelTests: XCTestCase {
    func testGIFResultHashable() {
        let a = GIFResult(id: "g1", mp4URL: "a.mp4", previewURL: "a.gif", width: 100, height: 200, title: "A")
        let b = GIFResult(id: "g1", mp4URL: "b.mp4", previewURL: "b.gif", width: 200, height: 300, title: "B")
        let c = GIFResult(id: "g2", mp4URL: "c.mp4", previewURL: "c.gif", width: 100, height: 200, title: "C")
        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, c)
        let set: Set<GIFResult> = [a, b, c]
        XCTAssertEqual(set.count, 2)
    }

    func testGIFProviderAllCases() {
        XCTAssertEqual(GIFProvider.allCases, [.giphy, .tenor, .imgur])
    }

    func testGIFProviderAPIKeyUserDefaultsKey() {
        XCTAssertEqual(GIFProvider.giphy.apiKeyUserDefaultsKey, "gifProviderAPIKey_giphy")
        XCTAssertEqual(GIFProvider.tenor.apiKeyUserDefaultsKey, "gifProviderAPIKey_tenor")
        XCTAssertEqual(GIFProvider.imgur.apiKeyUserDefaultsKey, "gifProviderAPIKey_imgur")
    }

    func testGIFProviderID() {
        XCTAssertEqual(GIFProvider.giphy.id, "GIPHY")
        XCTAssertEqual(GIFProvider.tenor.id, "Tenor")
        XCTAssertEqual(GIFProvider.imgur.id, "Imgur")
    }

    func testGIFErrorDescriptions() {
        XCTAssertEqual(GIFError.missingAPIKey("GIPHY").errorDescription, "GIPHY API key not configured. Add it in Settings.")
        XCTAssertEqual(GIFError.networkError("Timed out").errorDescription, "Timed out")
        XCTAssertEqual(GIFError.noResults.errorDescription, "No GIFs found")
    }

    func testGIFServiceSharedSingleton() {
        let a = GIFService.shared
        let b = GIFService.shared
        XCTAssertTrue(a === b)
    }
}
