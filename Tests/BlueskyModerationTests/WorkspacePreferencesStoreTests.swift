@testable import BlueskyModeration
import XCTest

@MainActor
final class WorkspacePreferencesStoreTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "WorkspacePreferencesTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        if let suiteName {
            defaults.removePersistentDomain(forName: suiteName)
        }
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testInitialState() {
        let store = WorkspacePreferencesStore(defaults: defaults)
        XCTAssertTrue(store.savedSearches.isEmpty)
        XCTAssertTrue(store.recentSearches.isEmpty)
        XCTAssertEqual(store.selectedTab, .moderation)
        XCTAssertEqual(store.lastProfileQuery, "")
    }

    func testSaveProfileSearch() {
        let store = WorkspacePreferencesStore(defaults: defaults)
        store.saveProfileSearch("safety")
        XCTAssertEqual(store.savedSearches.count, 1)
        XCTAssertEqual(store.savedSearches[0].query, "safety")
    }

    func testSaveProfileSearchTrimsWhitespace() {
        let store = WorkspacePreferencesStore(defaults: defaults)
        store.saveProfileSearch("  safety  ")
        XCTAssertEqual(store.savedSearches[0].query, "safety")
    }

    func testSaveProfileSearchEmptyIgnored() {
        let store = WorkspacePreferencesStore(defaults: defaults)
        store.saveProfileSearch("  ")
        XCTAssertTrue(store.savedSearches.isEmpty)
    }

    func testSaveProfileSearchDeduplicates() {
        let store = WorkspacePreferencesStore(defaults: defaults)
        store.saveProfileSearch("safety")
        store.saveProfileSearch("SAFETY")
        XCTAssertEqual(store.savedSearches.count, 1)
    }

    func testDeleteSavedSearch() {
        let store = WorkspacePreferencesStore(defaults: defaults)
        store.saveProfileSearch("test")
        let saved = store.savedSearches[0]
        store.deleteSavedSearch(saved)
        XCTAssertTrue(store.savedSearches.isEmpty)
    }

    func testNoteRecentSearch() {
        let store = WorkspacePreferencesStore(defaults: defaults)
        store.noteRecentSearch("alice.bsky.social")
        XCTAssertEqual(store.recentSearches.count, 1)
        XCTAssertEqual(store.recentSearches[0].query, "alice.bsky.social")
    }

    func testNoteRecentSearchDeduplicates() {
        let store = WorkspacePreferencesStore(defaults: defaults)
        store.noteRecentSearch("test")
        store.noteRecentSearch("test")
        XCTAssertEqual(store.recentSearches.count, 1)
    }

    func testRecentSearchLimit() {
        let store = WorkspacePreferencesStore(defaults: defaults)
        for i in 0 ..< 15 {
            store.noteRecentSearch("search\(i)")
        }
        XCTAssertEqual(store.recentSearches.count, 12)
    }

    func testNoteRecentSearchUpdatesSavedSearchTimestamp() {
        let store = WorkspacePreferencesStore(defaults: defaults)
        store.saveProfileSearch("safety")
        let saved = store.savedSearches[0]
        let oldDate = saved.lastUsedAt
        store.noteRecentSearch("safety")
        XCTAssertGreaterThan(store.savedSearches[0].lastUsedAt, oldDate)
    }

    func testPreviewPopulatesData() {
        let store = WorkspacePreferencesStore(defaults: defaults, preview: true)
        XCTAssertEqual(store.savedSearches.count, 2)
        XCTAssertEqual(store.recentSearches.count, 2)
        XCTAssertEqual(store.lastProfileQuery, "safety")
    }

    func testLastProfileQueryPersisted() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        let store1 = WorkspacePreferencesStore(defaults: defaults)
        store1.lastProfileQuery = "hello"
        let store2 = WorkspacePreferencesStore(defaults: defaults)
        XCTAssertEqual(store2.lastProfileQuery, "hello")
    }

    func testSavedSearchesSortedByLastUsed() {
        let store = WorkspacePreferencesStore(defaults: defaults)
        store.saveProfileSearch("alpha")
        store.saveProfileSearch("beta")
        store.saveProfileSearch("alpha")
        XCTAssertEqual(store.savedSearches[0].query, "alpha")
    }

    func testSelectedTabDefault() {
        let store = WorkspacePreferencesStore(defaults: defaults)
        XCTAssertEqual(store.selectedTab, .moderation)
    }

    func testSelectedTabPersisted() {
        let store1 = WorkspacePreferencesStore(defaults: defaults)
        store1.selectedTab = .account

        let store2 = WorkspacePreferencesStore(defaults: defaults)
        XCTAssertEqual(store2.selectedTab, .account)
    }

    func testRecentSearchEmptyIgnored() {
        let store = WorkspacePreferencesStore(defaults: defaults)
        store.noteRecentSearch("  ")
        XCTAssertTrue(store.recentSearches.isEmpty)
    }
}
