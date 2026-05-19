@testable import RULYX
import XCTest

final class UserAgentProviderTests: XCTestCase {
    func testRandomReturnsNonEmptyString() {
        let agent = UserAgentProvider.random
        XCTAssertFalse(agent.isEmpty)
    }

    func testRandomReturnsDifferentValues() {
        let agents = Set((0 ..< 50).map { _ in UserAgentProvider.random })
        XCTAssertGreaterThan(agents.count, 1)
    }
}

final class DashboardCacheTests: XCTestCase {
    override func tearDown() {
        super.tearDown()
        DashboardCache.clear(forKey: "test-key")
    }

    func testSaveAndLoad() {
        let data = DashboardCacheData(lists: [], profile: nil, blockingCount: nil, blockedByCount: nil)
        DashboardCache.save(data, forKey: "test-key")
        let loaded = DashboardCache.load(forKey: "test-key")
        XCTAssertNotNil(loaded)
    }

    func testLoadNonExistent() {
        DashboardCache.clear(forKey: "nonexistent")
        XCTAssertNil(DashboardCache.load(forKey: "nonexistent"))
    }

    func testClear() {
        let data = DashboardCacheData(lists: [], profile: nil, blockingCount: 5, blockedByCount: 2)
        DashboardCache.save(data, forKey: "test-key")
        DashboardCache.clear(forKey: "test-key")
        XCTAssertNil(DashboardCache.load(forKey: "test-key"))
    }

    func testOverwrite() {
        let first = DashboardCacheData(lists: [], profile: nil, blockingCount: 1, blockedByCount: 0)
        DashboardCache.save(first, forKey: "test-key")
        let second = DashboardCacheData(lists: [], profile: nil, blockingCount: 2, blockedByCount: 0)
        DashboardCache.save(second, forKey: "test-key")
        let loaded = DashboardCache.load(forKey: "test-key")
        XCTAssertEqual(loaded?.blockingCount, 2)
    }

    func testClearAll() {
        DashboardCache.save(DashboardCacheData(lists: [], profile: nil, blockingCount: nil, blockedByCount: nil), forKey: "key-a")
        DashboardCache.save(DashboardCacheData(lists: [], profile: nil, blockingCount: nil, blockedByCount: nil), forKey: "key-b")
        DashboardCache.clearAll()
        XCTAssertNil(DashboardCache.load(forKey: "key-a"))
        XCTAssertNil(DashboardCache.load(forKey: "key-b"))
    }
}

final class SpreadsheetExportTests: XCTestCase {
    func testGenerateXLSXReturnsNonNilData() {
        let data = SpreadsheetExport.generateXLSX(headers: ["Name", "Age"], rows: [["Alice", "30"], ["Bob", "25"]])
        XCTAssertNotNil(data)
        XCTAssertGreaterThan(data!.count, 0)
    }

    func testGenerateXLSXHasPKZipSignature() {
        let data = SpreadsheetExport.generateXLSX(headers: ["H"], rows: [["R"]])!
        XCTAssertEqual(data[0], 0x50)
        XCTAssertEqual(data[1], 0x4B)
        XCTAssertEqual(data[2], 0x03)
        XCTAssertEqual(data[3], 0x04)
    }

    func testGenerateODSReturnsNonNilData() {
        let data = SpreadsheetExport.generateODS(headers: ["Col"], rows: [["Val"]])
        XCTAssertNotNil(data)
        XCTAssertGreaterThan(data!.count, 0)
    }

    func testGenerateODSHasPKZipSignature() {
        let data = SpreadsheetExport.generateODS(headers: ["H"], rows: [["R"]])!
        XCTAssertEqual(data[0], 0x50)
        XCTAssertEqual(data[1], 0x4B)
        XCTAssertEqual(data[2], 0x03)
        XCTAssertEqual(data[3], 0x04)
    }

    func testXLSXWithEmptyRows() {
        let data = SpreadsheetExport.generateXLSX(headers: ["H1", "H2"], rows: [])
        XCTAssertNotNil(data)
    }

    func testODSWithEmptyRows() {
        let data = SpreadsheetExport.generateODS(headers: ["H1", "H2"], rows: [])
        XCTAssertNotNil(data)
    }

    func testXLSXWithSpecialCharacters() {
        let data = SpreadsheetExport.generateXLSX(headers: ["A&B"], rows: [["<escape>", "\"quote\""]])
        XCTAssertNotNil(data)
    }

    func testODSWithSpecialCharacters() {
        let data = SpreadsheetExport.generateODS(headers: ["A&B"], rows: [["<escape>"]])
        XCTAssertNotNil(data)
    }

    func testCRC32KnownValue() {
        let data = Data("Hello".utf8)
        let crc = crc32(data: data)
        XCTAssertEqual(crc, 0xF7D1_8982)
    }

    func testCRC32Empty() {
        let data = Data()
        let crc = crc32(data: data)
        XCTAssertEqual(crc, 0)
    }
}

private func crc32(data: Data) -> UInt32 {
    var table = [UInt32](repeating: 0, count: 256)
    for n in 0 ..< 256 {
        var c = UInt32(n)
        for _ in 0 ..< 8 {
            if c & 1 != 0 { c = 0xEDB8_8320 ^ (c >> 1) }
            else { c >>= 1 }
        }
        table[n] = c
    }
    var crc: UInt32 = 0xFFFF_FFFF
    for byte in data {
        crc = table[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8)
    }
    return crc ^ 0xFFFF_FFFF
}

@MainActor
final class BlueskyPushNotificationServiceTests: XCTestCase {
    private func makeService() -> (BlueskyPushNotificationService, MockRequestExecutor, MockSessionService) {
        let executor = MockRequestExecutor()
        let sessionService = MockSessionService()
        let service = BlueskyPushNotificationService(requestExecutor: executor, sessionService: sessionService)
        return (service, executor, sessionService)
    }

    func testRegisterPushSendsRequest() async throws {
        let (service, executor, _) = makeService()
        let account = AppAccount(handle: "test.bsky.social")
        let expectedPath = "app.bsky.notification.registerPush"
        executor.onSend = { path, method, _, _, _, _ in
            XCTAssertEqual(path, expectedPath)
            XCTAssertEqual(method, "POST")
            return EmptyResponse()
        }
        try await service.registerPush(serviceDID: "did:web:api.bsky.app", token: "abc123", appID: "com.ajung.RULYX", account: account, appPassword: "pass")
    }

    func testUnregisterPushSendsRequest() async throws {
        let (service, executor, _) = makeService()
        let account = AppAccount(handle: "test.bsky.social")
        let expectedPath = "app.bsky.notification.unregisterPush"
        executor.onSend = { path, method, _, _, _, _ in
            XCTAssertEqual(path, expectedPath)
            XCTAssertEqual(method, "POST")
            return EmptyResponse()
        }
        try await service.unregisterPush(serviceDID: "did:web:api.bsky.app", token: "abc123", appID: "com.ajung.RULYX", account: account, appPassword: "pass")
    }
}

@MainActor
final class AppLockManagerTests: XCTestCase {
    nonisolated(unsafe) private let manager = AppLockManager.shared

    nonisolated override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: "appLockEnabled")
        UserDefaults.standard.removeObject(forKey: "appLockTimeout")
        manager.isEnabled = false
        manager.isLocked = false
    }

    func testInitNotLockedWhenDisabled() {
        manager.isEnabled = false
        XCTAssertFalse(manager.isLocked)
    }

    func testDisableUnlocks() {
        manager.isEnabled = true
        manager.isLocked = true
        manager.isEnabled = false
        XCTAssertFalse(manager.isLocked)
    }

    func testBiometricLabelReturnsDefaultForSimulator() {
        let label = manager.biometricLabel
        XCTAssertTrue(["Touch ID", "Face ID", "Biometrics"].contains(label))
    }

    func testLockWhenDisabledDoesNothing() {
        manager.isEnabled = false
        manager.lock()
        XCTAssertFalse(manager.isLocked)
    }

    func testAppDidEnterBackgroundWithImmediateLock() {
        manager.isEnabled = true
        manager.timeoutMinutes = 0
        manager.appDidEnterBackground()
        XCTAssertTrue(manager.isLocked)
    }

    func testLockWhenEnabled() {
        manager.isEnabled = true
        manager.lock()
        XCTAssertTrue(manager.isLocked)
    }
}

@MainActor
final class iCloudAccountSyncTests: XCTestCase {
    nonisolated override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: "iCloudSyncEnabled")
    }

    func testInitEnabledByDefault() {
        UserDefaults.standard.removeObject(forKey: "iCloudSyncEnabled")
        let sync = iCloudAccountSync.shared
        XCTAssertTrue(sync.isEnabled)
    }

    func testSetEnabledPersists() {
        let sync = iCloudAccountSync.shared
        sync.isEnabled = false
        XCTAssertFalse(UserDefaults.standard.bool(forKey: "iCloudSyncEnabled"))
        sync.isEnabled = true
    }

    func testPushAccountsWhenDisabledDoesNothing() {
        let sync = iCloudAccountSync.shared
        sync.isEnabled = false
        let account = AppAccount(handle: "test.bsky.social", did: "did:plc:test")
        sync.pushAccounts([account])
        sync.isEnabled = true
    }
}
