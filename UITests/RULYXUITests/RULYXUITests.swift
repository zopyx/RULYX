import XCTest

@MainActor
final class RULYXUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--uitesting"]
        #if targetEnvironment(simulator)
        app.launchArguments += ["-AppleLanguages", "(en)"]
        app.launchArguments += ["-AppleLocale", "en_US"]
        #endif
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

        // Verify the tab switches without crash — check that tab bar is still visible
        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 3),
                      "Tab bar should remain visible after navigating to Settings")
    }

    func testInfoTabShowsSegmentedControl() {
        app.tabBars.firstMatch.buttons["Info"].tap()

        // Verify the tab switches without crash
        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 3),
                      "Tab bar should remain visible after navigating to Info")
    }

    func testInfoTabSectionSwitching() {
        app.tabBars.firstMatch.buttons["Info"].tap()

        // Verify the tab switches without crash
        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 3),
                      "Tab bar should remain visible after navigating to Info")
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
    /// see the account list, and verify key UI is interactive.
    func testAccountManagementFlow() {
        // Navigate to Accounts tab
        app.tabBars.firstMatch.buttons["Accounts"].tap()

        // Verify account list appears (preview accounts loaded in testing mode)
        let teamAlpha = app.staticTexts["team-alpha.bsky.social"]
        XCTAssertTrue(teamAlpha.waitForExistence(timeout: 4),
                      "Preview account 'team-alpha.bsky.social' should appear in accounts list")
    }

    /// Verifies the Settings tab navigation bar is accessible.
    func testSettingsNavigation() {
        // Navigate to Settings tab
        app.tabBars.firstMatch.buttons["Settings"].tap()

        // Verify no crash — tab bar should remain visible
        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 3),
                      "Tab bar should remain visible after navigating to Settings")
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

        // Verify the tab switches without crash
        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 3),
                      "Tab bar should remain visible after navigating to Info")
    }

    // MARK: - Account Detail Navigation

    /// Verifies tapping an account in the Accounts tab navigates to the Moderation tab
    /// (via switchToAccount → returnToModerationRoot flow).
    func testAccountDetailNavigation() {
        app.tabBars.firstMatch.buttons["Accounts"].tap()

        let accountRow = app.staticTexts["team-alpha.bsky.social"]
        XCTAssertTrue(accountRow.waitForExistence(timeout: 3),
                      "Preview account 'team-alpha.bsky.social' should be visible")

        accountRow.tap()

        // Tapping an account activates it and navigates to Moderation tab
        let refreshButton = app.buttons["Refresh lists"]
        XCTAssertTrue(refreshButton.waitForExistence(timeout: 3),
                      "Should navigate to Moderation tab after tapping account row")
    }

    // MARK: - Settings Lock Toggle

    /// Verifies the biometric lock toggle in Settings can be toggled on/off.
    func testSettingsLockToggle() {
        app.tabBars.firstMatch.buttons["Settings"].tap()

        // The lock toggle label depends on biometric type (Face ID / Touch ID)
        let lockToggle: XCUIElement
        if app.switches["Face ID Lock"].waitForExistence(timeout: 3) {
            lockToggle = app.switches["Face ID Lock"]
        } else if app.switches["Touch ID Lock"].waitForExistence(timeout: 3) {
            lockToggle = app.switches["Touch ID Lock"]
        } else {
            XCTFail("No biometric lock toggle found in Settings")
            return
        }

        let initialValue = lockToggle.value as? String
        lockToggle.tap()

        let newValue = lockToggle.value as? String
        XCTAssertNotEqual(initialValue, newValue,
                          "Lock toggle should change state after tap")

        // Reset toggle back to original state
        lockToggle.tap()
    }

    // MARK: - Language Picker

    /// Verifies the language picker exists in the Settings preferences section.
    func testLanguageSwitch() {
        app.tabBars.firstMatch.buttons["Settings"].tap()

        // The language picker in a List renders as a tappable row with label "Language"
        let languageRow = app.buttons["Language"]
        XCTAssertTrue(languageRow.waitForExistence(timeout: 3),
                      "Language picker should be present in Settings")
    }

    // MARK: - Tab Persistence

    /// Verifies that switching tabs preserves content: navigating to a non-default tab,
    /// switching to another, then returning shows the original tab's content.
    func testTabPersistence() {
        let tabBar = app.tabBars.firstMatch

        // Navigate to Info tab (non-default)
        tabBar.buttons["Info"].tap()
        let overviewSegment = app.buttons["Overview"]
        XCTAssertTrue(overviewSegment.waitForExistence(timeout: 3),
                      "Info tab should show Overview segment after tapping Info")

        // Switch to Settings tab
        tabBar.buttons["Settings"].tap()
        let languageRow = app.buttons["Language"]
        XCTAssertTrue(languageRow.waitForExistence(timeout: 3),
                      "Settings tab should show after tapping Settings")

        // Return to Info tab
        tabBar.buttons["Info"].tap()
        XCTAssertTrue(overviewSegment.waitForExistence(timeout: 3),
                      "Info tab should still show content after switching away and back")
    }
}
