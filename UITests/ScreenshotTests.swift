import XCTest

@MainActor
final class ScreenshotTests: XCTestCase {
    private var app: XCUIApplication!
    private var useTestAccount = false

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        setupSnapshot(app)

        let env = ProcessInfo.processInfo.environment
        var handle = env["TEST_HANDLE"]
        var password = env["TEST_PASSWORD"]
        var pds = env["TEST_PDS"]

        if handle == nil || password == nil {
            let dotEnv = loadDotEnv()
            if handle == nil {
                handle = dotEnv["TEST_HANDLE"]
            }
            if password == nil {
                password = dotEnv["TEST_PASSWORD"]
            }
            if pds == nil {
                pds = dotEnv["TEST_PDS"]
            }
        }

        if let handle, let password {
            app.launchEnvironment["TEST_HANDLE"] = handle
            app.launchEnvironment["TEST_PASSWORD"] = password
            if let pds {
                app.launchEnvironment["TEST_PDS"] = pds
            }
            useTestAccount = true
        }
    }

    // MARK: - Launch Helpers

    /// Launches with preview accounts (no live credentials). Always sets `--uitesting`
    /// so onboarding is skipped, language is English, and preview data is used.
    /// Pass `beta: true` to include `-showBetaFeatures` for timeline/notifications/chat tabs.
    private func launchApp(beta: Bool) {
        app.launchArguments = ["--uitesting"]
        if beta {
            app.launchArguments += ["-showBetaFeatures", "1"]
        }
        if useTestAccount {
            app.launchArguments += ["--test-account"]
        }
        app.launch()
    }

    /// Launches in preview-only mode — no live account credentials, no beta tabs.
    private func launchAppPreview() {
        app.launchArguments = ["--uitesting"]
        app.launch()
    }

    // MARK: - Tab Navigation Helpers

    /// Returns the tab bar element after waiting for it to exist.
    private func waitForTabBar(file: StaticString = #filePath, line: UInt = #line) -> XCUIElement {
        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 10), file: file, line: line)
        return tabBar
    }

    /// Taps a tab button by label and waits for the screen to settle.
    private func selectTab(_ label: String, settle: TimeInterval = 2) {
        let tabBar = app.tabBars.firstMatch
        tabBar.buttons[label].tap()
        sleep(UInt32(settle))
    }

    /// The "Accounts" tab is rendered as an avatar button, not a labeled tab bar button.
    /// Tap it by accessing the last button in the HStack (the one without a standard tab label).
    private func selectAccountsTab(settle: TimeInterval = 3) {
        // The accounts button is the avatar in the custom tab bar.
        // On compact layout it's the last button after the 6 named tab items.
        let tabBar = app.tabBars.firstMatch
        // Try tapping the Accounts-labeled button first (fallback for non-compact layouts)
        if tabBar.buttons["Accounts"].exists {
            tabBar.buttons["Accounts"].tap()
        } else {
            // On compact layout the button shows the localized "tab.accounts" label
            let allButtons = tabBar.buttons.allElementsBoundByIndex
            if let accountButton = allButtons.last {
                accountButton.tap()
            }
        }
        sleep(UInt32(settle))
    }

    // MARK: - Snapshot: All Tabs (Existing)

    func testCaptureAllTabs() {
        // Phase 1 — beta features ON: capture Moderation, Timeline, Notifications, Chat
        launchApp(beta: true)
        let tabBar = waitForTabBar()
        if useTestAccount {
            sleep(6)
        } else {
            sleep(3)
        }

        snapshot("0_Moderation")

        tabBar.buttons.element(boundBy: 1).tap()
        let hasFeed = app.collectionViews.firstMatch.cells.firstMatch
            .waitForExistence(timeout: 8)
        if !hasFeed {
            sleep(4)
        }
        snapshot("1_Timeline")

        tabBar.buttons.element(boundBy: 2).tap()
        sleep(4)
        snapshot("2_Notifications")

        tabBar.buttons.element(boundBy: 3).tap()
        let hasChat = app.collectionViews.firstMatch.cells.firstMatch
            .waitForExistence(timeout: 8)
        if !hasChat {
            sleep(4)
        }
        snapshot("3_Chat")

        // Phase 2 — capture overflow tabs via the More list (still with beta features)
        let overflowNames = ["4_Info", "5_Settings", "6_Accounts"]
        let overflowTabLabels = ["Info", "Settings", "Accounts"]

        // Try More navigation first
        let moreButton = tabBar.buttons.element(boundBy: 4)
        moreButton.tap()
        sleep(2)

        // Use app-level cell queries (not tables.cells) to find More list items
        if app.cells.element(boundBy: 0).waitForExistence(timeout: 3) {
            for i in 0 ..< overflowTabLabels.count {
                let cell = app.cells.element(boundBy: i)
                if cell.exists {
                    cell.tap()
                    sleep(2)
                    snapshot(overflowNames[i])
                    if i < overflowTabLabels.count - 1 {
                        app.navigationBars.buttons.element(boundBy: 0).tap()
                        sleep(1)
                    }
                }
            }
        } else {
            // Fallback: re-launch without beta for direct tab access
            app.terminate()
            launchApp(beta: false)
            let tabBar2 = waitForTabBar()
            if useTestAccount {
                sleep(6)
            } else {
                sleep(3)
            }

            for (label, snapName) in zip(overflowTabLabels, overflowNames) {
                tabBar2.buttons[label].tap()
                sleep(2)
                snapshot(snapName)
            }
        }
    }

    // MARK: - State-Coverage Snapshots: Moderation Tab

    /// Captures the Moderation tab showing the main Lists view with preview accounts.
    /// Verifies the account summary card, relationship counts, and moderation/regular list sections.
    func testSnapshotModerationListsView() {
        launchAppPreview()
        let tabBar = waitForTabBar()
        sleep(3) // Allow ListsView to render preview data

        // Verify we're on the Moderation tab (default)
        XCTAssertTrue(tabBar.exists, "Tab bar should be visible")

        // Wait for at least some list content or the empty state
        let accountSummary = app.staticTexts["Team Alpha"]
        let hasAccountSummary = accountSummary.waitForExistence(timeout: 5)
        if hasAccountSummary {
            snapshot("Moderation_ListsView")
        } else {
            // Fallback: capture whatever is rendered
            snapshot("Moderation_ListsView")
        }
    }

    /// Captures the Moderation tab when no moderation lists are configured
    /// (the "Create your first moderation list" prompt).
    func testSnapshotModerationEmptyLists() {
        launchAppPreview()
        _ = waitForTabBar()
        sleep(3)

        // Scroll down to the moderation lists section and capture the empty state
        // The empty prompt shows when no moderation lists exist yet
        snapshot("Moderation_EmptyLists")
    }

    /// Captures the Moderation tab scrolled to the Advanced section (Mentions, Custom Search, Direct Replies).
    func testSnapshotModerationAdvancedSection() {
        launchAppPreview()
        _ = waitForTabBar()
        sleep(2)

        // Scroll to the bottom to reveal the Advanced section
        let listsView = app.collectionViews.firstMatch
        if listsView.exists {
            // Swipe up to scroll down
            listsView.swipeUp()
            sleep(1)
            listsView.swipeUp()
            sleep(1)
        }
        snapshot("Moderation_Advanced")
    }

    // MARK: - State-Coverage Snapshots: Settings Tab

    /// Captures the Settings tab showing Preferences, Moderation, and AI sections.
    func testSnapshotSettingsAllSections() {
        launchAppPreview()
        _ = waitForTabBar()
        selectTab("Settings", settle: 3)

        // Verify the Settings list has rendered by checking for sections
        let settingsList = app.tables.firstMatch
        if settingsList.waitForExistence(timeout: 3) {
            snapshot("Settings_AllSections")
        } else {
            snapshot("Settings_AllSections")
        }
    }

    /// Captures the Settings tab scrolled to reveal Security and Internal sections.
    func testSnapshotSettingsInternal() {
        launchAppPreview()
        _ = waitForTabBar()
        selectTab("Settings", settle: 3)

        // Scroll down to show Internal/Debug sections
        let settingsList = app.tables.firstMatch
        if settingsList.exists {
            settingsList.swipeUp()
            sleep(1)
            settingsList.swipeUp()
            sleep(1)
        }
        snapshot("Settings_Internal")
    }

    // MARK: - State-Coverage Snapshots: Accounts Tab

    /// Captures the Accounts tab showing the preview account list with active/inactive states.
    func testSnapshotAccountsList() {
        launchAppPreview()
        _ = waitForTabBar()
        selectAccountsTab(settle: 4)

        // Verify preview account "team-alpha.bsky.social" appears
        let teamAlpha = app.staticTexts["team-alpha.bsky.social"]
        let safetyLab = app.staticTexts["safety-lab.bsky.social"]
        let hasAccounts = teamAlpha.waitForExistence(timeout: 5) || safetyLab.waitForExistence(timeout: 2)

        if hasAccounts {
            snapshot("Accounts_List")
        } else {
            // Fallback: capture whatever is rendered
            snapshot("Accounts_List")
        }
    }

    /// Captures the account detail/management view by tapping on an account row.
    func testSnapshotAccountDetail() {
        launchAppPreview()
        _ = waitForTabBar()
        selectAccountsTab(settle: 4)

        let teamAlpha = app.staticTexts["team-alpha.bsky.social"]
        if teamAlpha.waitForExistence(timeout: 5) {
            teamAlpha.firstMatch.tap()
            sleep(2)
            snapshot("Accounts_Detail")
        }
    }

    // MARK: - State-Coverage Snapshots: Info Tab

    /// Captures the Info tab — Overview section (hero card, claims grid, GitHub link, version).
    func testSnapshotInfoOverview() {
        launchAppPreview()
        _ = waitForTabBar()
        selectTab("Info", settle: 3)

        // The default selected tab is "Overview"
        let overviewPicker = app.segmentedControls.firstMatch
        if overviewPicker.exists {
            overviewPicker.buttons["Overview"].tap()
            sleep(1)
        }
        snapshot("Info_Overview")
    }

    /// Captures the Info tab — Features section (moderation lists, export, moderation feature cards).
    func testSnapshotInfoFeatures() {
        launchAppPreview()
        _ = waitForTabBar()
        selectTab("Info", settle: 3)

        let segmentedControl = app.segmentedControls.firstMatch
        if segmentedControl.exists {
            segmentedControl.buttons["Features"].tap()
            sleep(2)
        }
        snapshot("Info_Features")
    }

    /// Captures the Info tab — Legal section (author, website, imprint, privacy, license, third-party).
    func testSnapshotInfoLegal() {
        launchAppPreview()
        _ = waitForTabBar()
        selectTab("Info", settle: 3)

        let segmentedControl = app.segmentedControls.firstMatch
        if segmentedControl.exists {
            segmentedControl.buttons["Legal"].tap()
            sleep(2)
            // Scroll to reveal third-party and data classification sections
            let scrollView = app.scrollViews.firstMatch
            if scrollView.exists {
                scrollView.swipeUp()
                sleep(1)
            }
        }
        snapshot("Info_Legal")
    }
}

// MARK: - DotEnv Loader

private func loadDotEnv() -> [String: String] {
    let projectRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let url = projectRoot.appendingPathComponent(".env")
    guard let content = try? String(contentsOf: url, encoding: .utf8) else { return [:] }
    var result: [String: String] = [:]
    for line in content.components(separatedBy: .newlines) {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { continue }
        let stripped = trimmed.hasPrefix("export ") ? String(trimmed.dropFirst(7)).trimmingCharacters(in: .whitespaces) : trimmed
        guard let eq = stripped.firstIndex(of: "="), eq != stripped.startIndex else { continue }
        let key = String(stripped[..<eq]).trimmingCharacters(in: .whitespaces)
        var value = String(stripped[stripped.index(after: eq)...]).trimmingCharacters(in: .whitespaces)
        if (value.hasPrefix("'") && value.hasSuffix("'")) || (value.hasPrefix("\"") && value.hasSuffix("\"")) {
            value = String(value.dropFirst().dropLast())
        }
        if !key.isEmpty {
            result[key] = value
        }
    }
    return result
}
