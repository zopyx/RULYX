@testable import RULYX
import XCTest

@MainActor
final class FeedStoreTests: XCTestCase {
    private func makeStore(functionName: String = #function) -> FeedStore {
        let store = FeedStore(did: functionName)
        return store
    }

    nonisolated override func tearDown() {
        super.tearDown()
        UserDefaults.standard.removePersistentDomain(forName: #function)
    }

    func testInitialState() {
        let store = makeStore()
        XCTAssertNil(store.customFeedURI)
        XCTAssertEqual(store.customFeedName, String(localized: "timeline.following"))
        XCTAssertTrue(store.recentFeeds.isEmpty)
    }

    func testIsUsingCustomFeedFalseWhenURINil() {
        let store = makeStore()
        XCTAssertFalse(store.isUsingCustomFeed)
    }

    func testIsUsingCustomFeedFalseWhenURIEmpty() {
        let store = makeStore()
        store.setFeed(uri: "", name: "Test")
        XCTAssertFalse(store.isUsingCustomFeed)
    }

    func testIsUsingCustomFeedTrueWhenURIValid() {
        let store = makeStore()
        store.setFeed(uri: "at://feed/1", name: "Test Feed")
        XCTAssertTrue(store.isUsingCustomFeed)
    }

    func testSetFeedUpdatesProperties() {
        let store = makeStore()
        store.setFeed(uri: "at://feed/1", name: "My Feed")
        XCTAssertEqual(store.customFeedURI, "at://feed/1")
        XCTAssertEqual(store.customFeedName, "My Feed")
    }

    func testSetFeedAddsToRecentFeeds() {
        let store = makeStore()
        store.setFeed(uri: "at://feed/1", name: "Feed 1")
        XCTAssertEqual(store.recentFeeds.count, 1)
        XCTAssertEqual(store.recentFeeds[0].uri, "at://feed/1")
    }

    func testSetFeedDoesNotAddToRecentWhenURIEmpty() {
        let store = makeStore()
        store.setFeed(uri: "", name: "Empty")
        XCTAssertTrue(store.recentFeeds.isEmpty)
    }

    func testRecentFeedsDeduplicates() {
        let store = makeStore()
        store.addRecentFeed(uri: "at://feed/1", name: "Feed 1")
        store.addRecentFeed(uri: "at://feed/2", name: "Feed 2")
        store.addRecentFeed(uri: "at://feed/1", name: "Feed 1")
        XCTAssertEqual(store.recentFeeds.count, 2)
        XCTAssertEqual(store.recentFeeds[0].uri, "at://feed/1")
    }

    func testRecentFeedsMaxFive() {
        let store = makeStore()
        for i in 1 ... 6 {
            store.addRecentFeed(uri: "at://feed/\(i)", name: "Feed \(i)")
        }
        XCTAssertEqual(store.recentFeeds.count, 5)
    }

    func testResetToFollowing() {
        let store = makeStore()
        store.setFeed(uri: "at://feed/1", name: "Custom")
        store.resetToFollowing()
        XCTAssertNil(store.customFeedURI)
        XCTAssertEqual(store.customFeedName, String(localized: "timeline.following"))
    }

    func testPersistenceAcrossInstances() {
        let key = "testPersistence"
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: "feed_\(key)_customFeedURI")
        defaults.removeObject(forKey: "feed_\(key)_customFeedName")

        let store1 = FeedStore(did: key)
        store1.setFeed(uri: "at://feed/persist", name: "Persisted")

        let store2 = FeedStore(did: key)
        XCTAssertEqual(store2.customFeedURI, "at://feed/persist")
        XCTAssertEqual(store2.customFeedName, "Persisted")
    }

    func testSetAccountReloads() {
        let store = makeStore()
        store.setFeed(uri: "at://feed/1", name: "Old")
        store.setAccount(did: "new-did")
        XCTAssertNil(store.customFeedURI)
    }
}

@MainActor
final class MutedWordsStoreTests: XCTestCase {
    private let defaultsKey = "mutedWords"

    nonisolated override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: defaultsKey)
    }

    nonisolated override func tearDown() {
        super.tearDown()
        UserDefaults.standard.removeObject(forKey: defaultsKey)
    }

    func testInitialStateEmpty() {
        let store = MutedWordsStore()
        XCTAssertTrue(store.words.isEmpty)
    }

    func testAddWord() {
        let store = MutedWordsStore()
        store.add("badword")
        XCTAssertEqual(store.words, ["badword"])
        UserDefaults.standard.removeObject(forKey: defaultsKey)
    }

    func testAddTrimsWhitespace() {
        let store = MutedWordsStore()
        store.add("  spaced  ")
        XCTAssertEqual(store.words, ["spaced"])
        UserDefaults.standard.removeObject(forKey: defaultsKey)
    }

    func testAddEmptyDoesNothing() {
        let store = MutedWordsStore()
        store.add("")
        store.add("   ")
        XCTAssertTrue(store.words.isEmpty)
        UserDefaults.standard.removeObject(forKey: defaultsKey)
    }

    func testAddDuplicateDoesNothing() {
        UserDefaults.standard.removeObject(forKey: defaultsKey)
        let store = MutedWordsStore()
        store.add("word")
        store.add("word")
        XCTAssertEqual(store.words.count, 1)
        UserDefaults.standard.removeObject(forKey: defaultsKey)
    }

    func testContainsCaseInsensitive() {
        let store = MutedWordsStore()
        store.add("bad")
        XCTAssertTrue(store.contains("This is BAD stuff"))
        XCTAssertTrue(store.contains("bad"))
        XCTAssertFalse(store.contains("good stuff"))
        UserDefaults.standard.removeObject(forKey: defaultsKey)
    }

    func testRemoveAtIndex() {
        let store = MutedWordsStore()
        store.add("a")
        store.add("b")
        store.remove(at: 0)
        XCTAssertEqual(store.words, ["b"])
        UserDefaults.standard.removeObject(forKey: defaultsKey)
    }

    func testPersistence() {
        UserDefaults.standard.removeObject(forKey: defaultsKey)
        let store1 = MutedWordsStore()
        store1.add("persist-word")
        let store2 = MutedWordsStore()
        XCTAssertEqual(store2.words, ["persist-word"])
        UserDefaults.standard.removeObject(forKey: defaultsKey)
    }
}

@MainActor
final class AnalyticsStoreTests: XCTestCase {
    private nonisolated(unsafe) static let saveKey = "engagementSnapshots"

    nonisolated override func tearDown() {
        super.tearDown()
        UserDefaults.standard.removeObject(forKey: Self.saveKey)
    }

    func testInitialState() {
        let store = AnalyticsStore()
        XCTAssertTrue(store.snapshots.isEmpty)
    }

    func testRecordCreatesSnapshot() {
        let store = AnalyticsStore()
        store.record(postURI: "at://post/1", likeCount: 10, repostCount: 5, replyCount: 2)
        let history = store.history(for: "at://post/1")
        XCTAssertEqual(history.count, 1)
        XCTAssertEqual(history[0].likeCount, 10)
        XCTAssertEqual(history[0].repostCount, 5)
        XCTAssertEqual(history[0].replyCount, 2)
    }

    func testRecordAppendsMultiple() {
        let store = AnalyticsStore()
        store.record(postURI: "at://post/1", likeCount: 10, repostCount: 5, replyCount: 2)
        store.record(postURI: "at://post/1", likeCount: 15, repostCount: 8, replyCount: 3)
        let history = store.history(for: "at://post/1")
        XCTAssertEqual(history.count, 2)
    }

    func testRecordDifferentURIsSeparate() {
        let store = AnalyticsStore()
        store.record(postURI: "at://post/1", likeCount: 10, repostCount: 5, replyCount: 2)
        store.record(postURI: "at://post/2", likeCount: 20, repostCount: 10, replyCount: 4)
        XCTAssertEqual(store.history(for: "at://post/1").count, 1)
        XCTAssertEqual(store.history(for: "at://post/2").count, 1)
    }

    func testHistoryForUnknownURI() {
        let store = AnalyticsStore()
        XCTAssertTrue(store.history(for: "at://post/missing").isEmpty)
    }

    func testRetentionLimitFifty() {
        let store = AnalyticsStore()
        for i in 0 ..< 55 {
            store.record(postURI: "at://post/1", likeCount: i, repostCount: 0, replyCount: 0)
        }
        XCTAssertEqual(store.history(for: "at://post/1").count, 50)
        XCTAssertEqual(store.history(for: "at://post/1").first?.likeCount, 5)
    }

    func testLikeTrendUp() {
        let store = AnalyticsStore()
        store.record(postURI: "at://post/1", likeCount: 10, repostCount: 0, replyCount: 0)
        store.record(postURI: "at://post/1", likeCount: 25, repostCount: 0, replyCount: 0)
        XCTAssertEqual(store.likeTrend(for: "at://post/1"), "+15")
    }

    func testLikeTrendDown() {
        let store = AnalyticsStore()
        store.record(postURI: "at://post/1", likeCount: 25, repostCount: 0, replyCount: 0)
        store.record(postURI: "at://post/1", likeCount: 10, repostCount: 0, replyCount: 0)
        XCTAssertEqual(store.likeTrend(for: "at://post/1"), "-15")
    }

    func testLikeTrendFlat() {
        let store = AnalyticsStore()
        store.record(postURI: "at://post/1", likeCount: 10, repostCount: 0, replyCount: 0)
        store.record(postURI: "at://post/1", likeCount: 10, repostCount: 0, replyCount: 0)
        XCTAssertEqual(store.likeTrend(for: "at://post/1"), "→")
    }

    func testLikeTrendEmpty() {
        let store = AnalyticsStore()
        XCTAssertEqual(store.likeTrend(for: "at://post/1"), "")
    }

    func testLikeTrendSingleSnapshot() {
        let store = AnalyticsStore()
        store.record(postURI: "at://post/1", likeCount: 10, repostCount: 0, replyCount: 0)
        XCTAssertEqual(store.likeTrend(for: "at://post/1"), "")
    }

    func testPersistence() {
        UserDefaults.standard.removeObject(forKey: Self.saveKey)
        let store1 = AnalyticsStore()
        store1.record(postURI: "at://post/1", likeCount: 42, repostCount: 0, replyCount: 0)
        let store2 = AnalyticsStore()
        XCTAssertEqual(store2.history(for: "at://post/1").first?.likeCount, 42)
    }
}

@MainActor
final class BlueskySessionServiceTests: XCTestCase {
    private func makeService() -> (BlueskySessionService, MockRequestExecutor, MockKeychain) {
        let keychain = MockKeychain()
        let executor = MockRequestExecutor()
        let service = BlueskySessionService(requestExecutor: executor, keychain: keychain)
        return (service, executor, keychain)
    }

    func testAuthenticateSuccess() async throws {
        let (service, executor, _) = makeService()
        executor.onSend = { path, method, _, _, _, _ in
            XCTAssertEqual(path, "com.atproto.server.createSession")
            XCTAssertEqual(method, "POST")
            return CreateSessionResponse(did: "did:plc:test", handle: "test.bsky.social", accessJWT: "jwt", refreshJWT: "refresh", didDoc: nil)
        }
        let session = try await service.authenticate(handle: "test.bsky.social", appPassword: "password")
        XCTAssertEqual(session.did, "did:plc:test")
        XCTAssertEqual(session.handle, "test.bsky.social")
        XCTAssertEqual(session.accessJWT, "jwt")
    }

    func testPersistSession() async throws {
        let (service, _, keychain) = makeService()
        let account = AppAccount(handle: "test.bsky.social")
        let session = BlueskySession(did: "did:plc:t", handle: "test.bsky.social", accessJWT: "jwt", refreshJWT: nil, pdsURL: URL(string: "https://bsky.social")!)
        try await service.persistSession(session, for: account)
        let saved = keychain.savedValues["com.ajung.RULYX.session:\(account.id.uuidString)"]
        XCTAssertNotNil(saved)
        XCTAssertTrue(saved!.contains("did:plc:t"))
    }

    func testDeletePersistedSession() async throws {
        let (service, _, keychain) = makeService()
        let account = AppAccount(handle: "test.bsky.social")
        let session = BlueskySession(did: "did:plc:t", handle: "test.bsky.social", accessJWT: "jwt", refreshJWT: nil, pdsURL: URL(string: "https://bsky.social")!)
        try await service.persistSession(session, for: account)
        try service.deletePersistedSession(for: account)
        XCTAssertNil(keychain.savedValues["com.ajung.RULYX.session:\(account.id.uuidString)"])
    }

    func testClearSessionCache() {
        let (service, _, _) = makeService()
        let account = AppAccount(handle: "test")
        let session = BlueskySession(did: "did:plc:t", handle: "test.bsky.social", accessJWT: "jwt", refreshJWT: nil, pdsURL: URL(string: "https://bsky.social")!)
        let exp = XCTestExpectation()
        Task {
            try await service.persistSession(session, for: account)
            service.clearSessionCache()
            exp.fulfill()
        }
        wait(for: [exp], timeout: 1)
    }

    func testAuthenticateWithEntrywayURL() async throws {
        let (service, executor, _) = makeService()
        executor.onSend = { path, _, _, _, _, hostURL in
            XCTAssertEqual(path, "com.atproto.server.createSession")
            XCTAssertEqual((hostURL as? URL)?.absoluteString, "https://pds.example.com")
            return CreateSessionResponse(did: "did:plc:test", handle: "test.bsky.social", accessJWT: "jwt", refreshJWT: nil, didDoc: nil)
        }
        let session = try await service.authenticate(handle: "test.bsky.social", appPassword: "pw", entrywayURL: URL(string: "https://pds.example.com")!)
        XCTAssertEqual(session.did, "did:plc:test")
    }
}

@MainActor
final class HTTPClientTests: XCTestCase {
    nonisolated(unsafe) private var session: URLSession!

    nonisolated override func setUp() {
        super.setUp()
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        session = URLSession(configuration: config)
    }

    nonisolated override func tearDown() {
        super.tearDown()
        MockURLProtocol.requestHandler = nil
        session = nil
    }

    func testDataForRequestSuccess() async throws {
        let expectedData = Data("{\"key\":\"value\"}".utf8)
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, expectedData)
        }
        let client = HTTPClient(session: session)
        let request = URLRequest(url: URL(string: "https://example.com/api")!)
        let (data, response) = try await client.data(for: request)
        XCTAssertEqual(data, expectedData)
        XCTAssertEqual(response.statusCode, 200)
    }

    func testDataForRequestUserAgentSet() async throws {
        MockURLProtocol.requestHandler = { request in
            XCTAssertNotNil(request.value(forHTTPHeaderField: "User-Agent"))
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data())
        }
        let client = HTTPClient(session: session)
        let request = URLRequest(url: URL(string: "https://example.com/api")!)
        _ = try await client.data(for: request)
    }

    func testDataForRequestThrowsOnNonHTTPResponse() async throws {
        MockURLProtocol.requestHandler = { _ in
            throw URLError(.badServerResponse)
        }
        let client = HTTPClient(session: session)
        let request = URLRequest(url: URL(string: "https://example.com/api")!)
        do {
            _ = try await client.data(for: request)
            XCTFail("Expected error")
        } catch {
            XCTAssertTrue(error is URLError)
        }
    }

    func testDataFromURLSuccess() async throws {
        let expectedData = Data("test".utf8)
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, expectedData)
        }
        let client = HTTPClient(session: session)
        let (data, _) = try await client.data(from: URL(string: "https://example.com")!)
        XCTAssertEqual(String(data: data, encoding: .utf8), "test")
    }
}
