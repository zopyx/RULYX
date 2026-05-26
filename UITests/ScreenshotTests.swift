import XCTest

@MainActor
final class ScreenshotTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        setupSnapshot(app)
        app.launchArguments = ["--uitesting"]
        app.launch()
    }

    func testCaptureMainScreen() {
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 10))
        sleep(3)
        snapshot("ModerationMainScreen")
    }
}
