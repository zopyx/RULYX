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

    func testGIFErrorDescriptions() {
        XCTAssertEqual(GIFError.missingAPIKey.errorDescription, "KLIPY API key not configured. Add it in Settings.")
        XCTAssertEqual(GIFError.networkError("Timed out").errorDescription, "Timed out")
        XCTAssertEqual(GIFError.noResults.errorDescription, "No GIFs found")
        XCTAssertEqual(GIFError.invalidURL.errorDescription, "GIF service URL is invalid.")
        XCTAssertEqual(GIFError.tooLarge.errorDescription, "GIF is too large to attach.")
    }

    func testGIFServiceSharedSingleton() {
        let a = GIFService.shared
        let b = GIFService.shared
        XCTAssertTrue(a === b)
    }

    func testSeedKeyIfNeededStoresBundledKey() throws {
        let keychain = MockKeychain()

        GIFService.seedKeyIfNeeded(in: keychain)

        let value = try keychain.read(
            service: GIFService.keychainService,
            account: GIFService.keychainAccount
        )
        XCTAssertFalse(value?.isEmpty ?? true)
    }

    func testSeedKeyIfNeededDoesNotOverwriteExistingKey() throws {
        let keychain = MockKeychain()
        try keychain.save(
            "existing-key",
            service: GIFService.keychainService,
            account: GIFService.keychainAccount
        )

        GIFService.seedKeyIfNeeded(in: keychain)

        let value = try keychain.read(
            service: GIFService.keychainService,
            account: GIFService.keychainAccount
        )
        XCTAssertEqual(value, "existing-key")
    }
}
