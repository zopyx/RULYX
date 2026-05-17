import XCTest

@MainActor
final class BlueskyModerationUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--uitesting"]
        app.launch()
    }

    // MARK: - Existing Tests

    func testAppLaunches() {
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 5))
    }

    func testTabNavigation() {
        let tabBar = app.tabBars.firstMatch
        let tabNames = tabBar.buttons.allElementsBoundByIndex.map(\.label)
        XCTAssertTrue(tabNames.contains("Moderation"), "Got: \(tabNames)")
        XCTAssertTrue(tabNames.contains("Settings"), "Got: \(tabNames)")
        XCTAssertTrue(tabNames.contains("Info"), "Got: \(tabNames)")
        XCTAssertTrue(tabNames.contains("Accounts"), "Got: \(tabNames)")

        tabBar.buttons["Settings"].tap()
        tabBar.buttons["Info"].tap()
        tabBar.buttons["Accounts"].tap()
        tabBar.buttons["Moderation"].tap()
    }

    func testModerationTabShowsContent() {
        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.buttons["Moderation"].exists)
    }

    func testAccountsTabShowsPreviewAccounts() {
        app.tabBars.firstMatch.buttons["Accounts"].tap()

        let teamAlpha = app.staticTexts["team-alpha.bsky.social"]
        XCTAssertTrue(teamAlpha.waitForExistence(timeout: 3))
    }

    func testSettingsTabShowsPreferences() {
        app.tabBars.firstMatch.buttons["Settings"].tap()

        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 3))
    }

    func testInfoTabShowsSegmentedControl() {
        app.tabBars.firstMatch.buttons["Info"].tap()

        let overviewButton = app.buttons["Overview"]
        XCTAssertTrue(overviewButton.waitForExistence(timeout: 3))
    }

    func testInfoTabSectionSwitching() {
        app.tabBars.firstMatch.buttons["Info"].tap()

        let featuresButton = app.buttons["Features"]
        XCTAssertTrue(featuresButton.waitForExistence(timeout: 3))
        featuresButton.tap()

        let legalButton = app.buttons["Legal"]
        XCTAssertTrue(legalButton.waitForExistence(timeout: 1))
    }

    // MARK: - Phase 6: UX Reliability Tests

    /// Verifies that onboarding is automatically skipped in testing mode
    /// and the main moderation content is shown directly.
    func testOnboardingSkip() {
        // With --uitesting, onboarding is auto-dismissed via hasSeenOnboarding
        // Verify we land on the moderation tab with its toolbar visible
        let refreshButton = app.buttons["Refresh lists"]
        XCTAssertTrue(refreshButton.waitForExistence(timeout: 3),
                      "Moderation toolbar refresh button should be visible after onboarding skip")

        // Confirm tab bar is visible (we're in the main app, not stuck on onboarding)
        XCTAssertTrue(app.tabBars.firstMatch.exists, "Tab bar should be visible in main app")
    }

    /// Verifies the full account management flow: navigate to Accounts tab,
    /// see the account list, enter edit mode, and verify edit mode activates.
    func testAccountManagementFlow() {
        // Navigate to Accounts tab
        app.tabBars.firstMatch.buttons["Accounts"].tap()

        // Verify account list appears (preview accounts loaded in testing mode)
        let teamAlpha = app.staticTexts["team-alpha.bsky.social"]
        XCTAssertTrue(teamAlpha.waitForExistence(timeout: 3),
                      "Preview account 'team-alpha.bsky.social' should appear in accounts list")

        // Tap the Edit button to activate edit mode
        let editButton = app.buttons["Edit"]
        XCTAssertTrue(editButton.exists, "Edit button should be present in account toolbar")
        editButton.tap()

        // Verify edit mode activates — the Edit button should change to Done
        let doneButton = app.buttons["Done"]
        XCTAssertTrue(doneButton.waitForExistence(timeout: 2),
                      "Done button should appear when edit mode is active")
    }

    /// Verifies the Settings tab navigation bar is accessible.
    func testSettingsNavigation() {
        // Navigate to Settings tab
        app.tabBars.firstMatch.buttons["Settings"].tap()

        // Verify the Settings navigation bar exists
        let settingsNavBar = app.navigationBars["Settings"]
        XCTAssertTrue(settingsNavBar.waitForExistence(timeout: 3),
                      "Settings navigation bar should be visible")
    }

    /// Verifies the Moderation tab's refresh button has proper accessibility label.
    func testModerationTabAccessibility() {
        // Default tab is Moderation — verify the refresh button exists with correct label
        let refreshButton = app.buttons["Refresh lists"]
        XCTAssertTrue(refreshButton.waitForExistence(timeout: 3),
                      "Refresh lists button should exist on moderation tab")
        XCTAssertEqual(refreshButton.label, "Refresh lists",
                       "Refresh button should have correct accessibility label")
    }

    // MARK: - InfoView Tab Switching Tests

    /// Verifies that InfoView content appears correctly for each tab and switching
    /// between tabs maintains a consistent view (no blank screens, no crashes).
    func testInfoViewAllTabsShowContent() {
        app.tabBars.firstMatch.buttons["Info"].tap()

        // Overview tab should show key content
        let overviewButton = app.buttons["Overview"]
        XCTAssertTrue(overviewButton.waitForExistence(timeout: 3))

        let titleText = app.staticTexts["Bluesky moderation made easy"]
        XCTAssertTrue(titleText.exists, "Overview tab should show app title")

        // Switch to Features tab
        app.buttons["Features"].tap()
        let featuresTitle = app.staticTexts["Lists & Members"]
        XCTAssertTrue(featuresTitle.waitForExistence(timeout: 2),
                      "Features tab should show list features content")

        // Switch to Legal tab
        app.buttons["Legal"].tap()
        let legalAuthor = app.staticTexts["Andreas Jung"]
        XCTAssertTrue(legalAuthor.waitForExistence(timeout: 2),
                      "Legal tab should show author info")

        // Switch back to Overview and verify content reappears
        app.buttons["Overview"].tap()
        XCTAssertTrue(titleText.waitForExistence(timeout: 2),
                      "Overview content should reappear after switching back from Legal")
    }
}
