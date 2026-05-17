@testable import BlueskyModeration
import XCTest

final class KeychainServiceTests: XCTestCase {
    private var keychain: MockKeychain!

    override func setUp() {
        super.setUp()
        keychain = MockKeychain()
    }

    override func tearDown() {
        keychain = nil
        super.tearDown()
    }

    func testSaveAndRead() throws {
        try keychain.save("secret-value", service: "test-service", account: "test-account")
        let value = try keychain.read(service: "test-service", account: "test-account")
        XCTAssertEqual(value, "secret-value")
    }

    func testReadNonExistentReturnsNil() throws {
        let value = try keychain.read(service: "nonexistent", account: "nonexistent")
        XCTAssertNil(value)
    }

    func testDeleteRemovesValue() throws {
        try keychain.save("value", service: "s", account: "a")
        try keychain.delete(service: "s", account: "a")
        let value = try keychain.read(service: "s", account: "a")
        XCTAssertNil(value)
    }

    func testDeleteNonExistentDoesNotThrow() {
        XCTAssertNoThrow(try keychain.delete(service: "nonexistent", account: "nonexistent"))
    }

    func testOverwriteExistingValue() throws {
        try keychain.save("original", service: "s", account: "a")
        try keychain.save("updated", service: "s", account: "a")
        let value = try keychain.read(service: "s", account: "a")
        XCTAssertEqual(value, "updated")
    }

    func testMultipleAccountsIndependent() throws {
        try keychain.save("value1", service: "s", account: "a1")
        try keychain.save("value2", service: "s", account: "a2")
        XCTAssertEqual(try keychain.read(service: "s", account: "a1"), "value1")
        XCTAssertEqual(try keychain.read(service: "s", account: "a2"), "value2")
    }

    func testMultipleServicesIndependent() throws {
        try keychain.save("s1v", service: "s1", account: "a")
        try keychain.save("s2v", service: "s2", account: "a")
        XCTAssertEqual(try keychain.read(service: "s1", account: "a"), "s1v")
        XCTAssertEqual(try keychain.read(service: "s2", account: "a"), "s2v")
    }

    func testMixedCaseKeyComponents() throws {
        try keychain.save("mixed", service: "MyService", account: "MyAccount")
        XCTAssertEqual(try keychain.read(service: "MyService", account: "MyAccount"), "mixed")
    }
}
