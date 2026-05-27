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
            if handle == nil { handle = dotEnv["TEST_HANDLE"] }
            if password == nil { password = dotEnv["TEST_PASSWORD"] }
            if pds == nil { pds = dotEnv["TEST_PDS"] }
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

    private func launchApp(beta: Bool) {
        app.launchArguments = ["--uitesting"]
        if beta { app.launchArguments += ["-showBetaFeatures", "1"] }
        if useTestAccount { app.launchArguments += ["--test-account"] }
        app.launch()
    }

    func testCaptureAllTabs() throws {
        // Phase 1 — beta features ON: capture Moderation, Timeline, Notifications, Chat
        launchApp(beta: true)
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 10))
        if useTestAccount { sleep(6) } else { sleep(3) }

        let tabBar = app.tabBars.firstMatch
        snapshot("0_Moderation")

        tabBar.buttons.element(boundBy: 1).tap()
        let hasFeed = app.collectionViews.firstMatch.cells.firstMatch
            .waitForExistence(timeout: 8)
        if !hasFeed { sleep(4) }
        snapshot("1_Timeline")

        tabBar.buttons.element(boundBy: 2).tap()
        sleep(4)
        snapshot("2_Notifications")

        tabBar.buttons.element(boundBy: 3).tap()
        let hasChat = app.collectionViews.firstMatch.cells.firstMatch
            .waitForExistence(timeout: 8)
        if !hasChat { sleep(4) }
        snapshot("3_Chat")

        // Phase 2 — capture overflow tabs via the More list (still with beta features)
        // Phase 3 — fallback: re-launch without beta if More navigation fails
        let overflowNames = ["4_Info", "5_Settings", "6_Accounts"]
        let overflowTabLabels = ["Info", "Settings", "Accounts"]

        // Try More navigation first
        let moreButton = tabBar.buttons.element(boundBy: 4)
        moreButton.tap()
        sleep(2)

        // Use app-level cell queries (not tables.cells) to find More list items
        if app.cells.element(boundBy: 0).waitForExistence(timeout: 3) {
            for i in 0..<overflowTabLabels.count {
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
            XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 10))
            if useTestAccount { sleep(6) } else { sleep(3) }

            for (label, snapName) in zip(overflowTabLabels, overflowNames) {
                app.tabBars.buttons[label].tap()
                sleep(2)
                snapshot(snapName)
            }
        }
    }
}

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
        if !key.isEmpty { result[key] = value }
    }
    return result
}
