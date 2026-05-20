@testable import RULYX
import XCTest

@MainActor
final class AppLockManagerTimeoutTests: XCTestCase {
    private var lockManager: AppLockManager!
    private var currentTime: Date!

    override func setUp() {
        super.setUp()
        currentTime = Date()
        lockManager = AppLockManager.shared
        lockManager.isEnabled = true
        lockManager.timeoutMinutes = 5
        lockManager.isLocked = false
        lockManager.now = { self.currentTime }
    }

    override func tearDown() {
        lockManager.isEnabled = false
        lockManager = nil
        currentTime = nil
        super.tearDown()
    }

    func testLockOnForegroundAfterTimeout() {
        lockManager.appDidEnterBackground()
        currentTime = currentTime.addingTimeInterval(5 * 60 + 1)
        lockManager.appDidBecomeActive()
        XCTAssertTrue(lockManager.isLocked)
    }

    func testNoLockWhenTimeoutNotElapsed() {
        lockManager.appDidEnterBackground()
        currentTime = currentTime.addingTimeInterval(2 * 60)
        lockManager.appDidBecomeActive()
        XCTAssertFalse(lockManager.isLocked)
    }

    func testInstantLockWhenTimeoutMinutesIsZero() {
        lockManager.timeoutMinutes = 0
        lockManager.appDidEnterBackground()
        XCTAssertTrue(lockManager.isLocked)
    }

    func testNoLockWhenDisabled() {
        lockManager.isEnabled = false
        lockManager.appDidEnterBackground()
        lockManager.appDidBecomeActive()
        XCTAssertFalse(lockManager.isLocked)
    }

    func testLockAfterExactTimeout() {
        lockManager.appDidEnterBackground()
        currentTime = currentTime.addingTimeInterval(5 * 60)
        lockManager.appDidBecomeActive()
        XCTAssertTrue(lockManager.isLocked)
    }
}
