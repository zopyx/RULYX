@testable import RULYX
import XCTest

@MainActor
final class ProtectedDataStoreTests: XCTestCase {
    private nonisolated(unsafe) var tempDirectory: URL!
    private nonisolated(unsafe) var suite: UserDefaults!

    override nonisolated func setUp() {
        super.setUp()
        let suiteName = "ProtectedDataStoreTests.\(UUID().uuidString)"
        suite = UserDefaults(suiteName: suiteName)
        suite?.removePersistentDomain(forName: suiteName)
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ProtectedDataStoreTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        tempDirectory = directory
    }

    override nonisolated func tearDown() {
        if let tempDirectory {
            try? FileManager.default.removeItem(at: tempDirectory)
        }
        tempDirectory = nil
        suite = nil
        super.tearDown()
    }

    private func makeStore(name: String, key: String) -> ProtectedDataStore {
        ProtectedDataStore(name: name, legacyKey: key, defaults: suite, directory: tempDirectory)
    }

    func testWriteThenReadRoundtrip() {
        let store = makeStore(name: "roundtrip", key: "test.roundtrip")
        let payload = Data("hello".utf8)

        store.set(payload)

        XCTAssertEqual(store.data(), payload)
    }

    func testReadReturnsNilWhenNothingStored() {
        let store = makeStore(name: "empty", key: "test.empty")

        XCTAssertNil(store.data())
    }

    func testMigratesLegacyUserDefaultsValueAndRemovesIt() {
        let legacy = Data("legacy".utf8)
        suite.set(legacy, forKey: "test.migration")

        let store = makeStore(name: "migration", key: "test.migration")

        // First read migrates: returns the legacy value, writes the file, clears the suite.
        XCTAssertEqual(store.data(), legacy)
        XCTAssertNil(suite.data(forKey: "test.migration"))

        // Second store instance reads from the migrated file only.
        let store2 = makeStore(name: "migration", key: "test.migration")
        XCTAssertEqual(store2.data(), legacy)
    }

    func testInjectedSuiteWithoutDirectoryStaysInUserDefaults() {
        let store = ProtectedDataStore(name: "suite-mode", legacyKey: "test.suitemode", defaults: suite)
        let payload = Data("suite".utf8)

        store.set(payload)

        XCTAssertEqual(suite.data(forKey: "test.suitemode"), payload)
        XCTAssertEqual(store.data(), payload)
    }
}
