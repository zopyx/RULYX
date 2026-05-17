@testable import BlueskyModeration
import XCTest

@MainActor
final class LiveAuthenticationTests: XCTestCase {
    func testLoginLogoutWithLiveBlueskyAccount() async throws {
        let credentials = try liveCredentials()
        let keychain = TestKeychainService()
        let defaults = try XCTUnwrap(UserDefaults(suiteName: #function))
        defaults.removePersistentDomain(forName: #function)

        let requestExecutor = BlueskyRequestExecutor()
        let sessionService = BlueskySessionService(
            requestExecutor: requestExecutor,
            keychain: keychain
        )
        let client = LiveBlueskyClient(
            requestExecutor: requestExecutor,
            sessionService: sessionService
        )
        let store = AccountStore(defaults: defaults, keychain: keychain)

        let added = await store.addAccount(
            handle: credentials.handle,
            appPassword: credentials.appPassword,
            client: client
        )

        XCTAssertTrue(added, store.errorMessage ?? "Expected live login to succeed.")
        XCTAssertEqual(store.accounts.count, 1)

        guard let account = store.activeAccount else {
            return XCTFail("Expected an active account after login.")
        }

        XCTAssertEqual(account.handle, credentials.handle)
        XCTAssertEqual(store.appPassword(for: account), credentials.appPassword)
        XCTAssertTrue(
            keychain.containsValue(
                service: "com.ajung.BlueskyModeration.session",
                account: account.id.uuidString
            ),
            "Expected persisted session to be stored after login."
        )

        store.removeAccount(account, client: client)

        XCTAssertTrue(store.accounts.isEmpty)
        XCTAssertNil(store.activeAccount)
        XCTAssertNil(store.appPassword(for: account))
        XCTAssertFalse(
            keychain.containsValue(
                service: "com.ajung.BlueskyModeration.password",
                account: account.id.uuidString
            ),
            "Expected saved password to be deleted on logout."
        )
        XCTAssertFalse(
            keychain.containsValue(
                service: "com.ajung.BlueskyModeration.session",
                account: account.id.uuidString
            ),
            "Expected persisted session to be deleted on logout."
        )
    }

    private func liveCredentials() throws -> (handle: String, appPassword: String) {
        let env = ProcessInfo.processInfo.environment
        if let handle = env["BLUESKY_TEST_USER"], let password = env["BLUESKY_TEST_PASSWORD"],
           !handle.isEmpty, !password.isEmpty
        {
            return (handle, password)
        }

        let envURL = repositoryRootURL()
            .appendingPathComponent(".env")
        guard FileManager.default.fileExists(atPath: envURL.path) else {
            XCTFail("Missing BLUESKY_TEST_USER/BLUESKY_TEST_PASSWORD environment variables or .env file at \(envURL.path)")
            throw LiveAuthenticationTestError.missingCredentials(envURL.path)
        }

        let fileContents = try String(contentsOf: envURL, encoding: .utf8)
        let values = dotenvValues(from: fileContents)

        guard let handle = values["BLUESKY_TEST_USER"], !handle.isEmpty else {
            XCTFail("BLUESKY_TEST_USER is missing from \(envURL.path)")
            throw LiveAuthenticationTestError.missingKey("BLUESKY_TEST_USER")
        }

        guard let appPassword = values["BLUESKY_TEST_PASSWORD"], !appPassword.isEmpty else {
            XCTFail("BLUESKY_TEST_PASSWORD is missing from \(envURL.path)")
            throw LiveAuthenticationTestError.missingKey("BLUESKY_TEST_PASSWORD")
        }

        return (handle, appPassword)
    }

    private func repositoryRootURL() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func dotenvValues(from fileContents: String) -> [String: String] {
        fileContents
            .split(whereSeparator: \.isNewline)
            .reduce(into: [String: String]()) { values, rawLine in
                let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !line.isEmpty, !line.hasPrefix("#") else { return }
                let normalizedLine = line.hasPrefix("export ") ? String(line.dropFirst("export ".count)) : line
                guard let separatorIndex = normalizedLine.firstIndex(of: "=") else { return }
                let key = normalizedLine[..<separatorIndex].trimmingCharacters(in: .whitespacesAndNewlines)
                let value = normalizedLine[normalizedLine.index(after: separatorIndex)...]
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
                guard !key.isEmpty else { return }
                values[key] = value
            }
    }
}

private enum LiveAuthenticationTestError: Error {
    case missingCredentials(String)
    case missingKey(String)
}

private final class TestKeychainService: KeychainServicing {
    private var values: [String: String] = [:]

    func save(_ value: String, service: String, account: String) throws {
        values[key(service: service, account: account)] = value
    }

    func read(service: String, account: String) throws -> String? {
        values[key(service: service, account: account)]
    }

    func delete(service: String, account: String) throws {
        values.removeValue(forKey: key(service: service, account: account))
    }

    func containsValue(service: String, account: String) -> Bool {
        values[key(service: service, account: account)] != nil
    }

    private func key(service: String, account: String) -> String {
        "\(service):\(account)"
    }
}
