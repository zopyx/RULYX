# Testing Patterns

**Analysis Date:** 2026-05-12

## Test Framework

**Runner:** XCTest (bundled with Xcode)

**Config:** `project.yml` defines two test targets:
- `BlueskyModerationTests` — unit tests (line 39-50)
  - Type: `bundle.unit-test`
  - Sources: `Tests/`
  - Depends on: `BlueskyModeration`
- `BlueskyModerationUITests` — UI tests (line 51-62)
  - Type: `bundle.ui-testing`
  - Sources: `UITests/`
  - Depends on: `BlueskyModeration`

**Run Commands:**
```bash
# Via scheme (runs both test targets)
xcodebuild -project BlueskyModeration.xcodeproj -scheme BlueskyModeration -destination 'generic/platform=iOS Simulator' build-for-testing CODE_SIGNING_ALLOWED=NO

# Run from Xcode: Product → Test (Cmd+U)
```

## Test File Organization

**Location:** All unit tests in `Tests/BlueskyModerationTests/`

**Naming:** `{TypeName}Tests.swift` — matches tested type name exactly.

**Test files (26 total):**

| Test File | Tests What |
|-----------|-----------|
| `AppErrorTests.swift` | `AppError` normalization, error categorization |
| `AccountStoreTests.swift` | `AccountStore` add/persist, keychain integration |
| `ActionQueueStoreTests.swift` | `ActionQueueStore` enqueue/cancel/retry, state management |
| `BlueskyAPIDTOsTests.swift` | API DTO JSON decoding (296 lines, most thorough decoder tests) |
| `BlueskyListServiceTests.swift` | `BlueskyListService` fetch lists, pagination (199 lines) |
| `BlueskyProfileServiceTests.swift` | `BlueskyProfileService` profile fetch, search |
| `BlueskyRequestExecutorTests.swift` | HTTP request/response handling, auth headers, error mapping (230 lines) |
| `KeychainServiceTests.swift` | Keychain read/write/delete operations |
| `ListBatchControllerTests.swift` | Batch add/remove operations, progress, error handling (183 lines) |
| `ListDetailViewModelTests.swift` | `ListDetailViewModel` state management |
| `ListDiffControllerTests.swift` | List comparison logic |
| `ListImportControllerTests.swift` | Import preview classification (ready/already/duplicate/unresolved) |
| `ListMembersControllerTests.swift` | Paginated member loading, deduplication (146 lines) |
| `ListsViewModelTests.swift` | `ListsViewModel` list management, cache |
| `LiveAuthenticationTests.swift` | Live auth endpoint testing |
| `LiveBlueskyClientTests.swift` | `LiveBlueskyClient` delegation, PLC audit, blocklist |
| `LoadableStateTests.swift` | `LoadableState` state machine transitions (67 lines) |
| `ModerationAuditStoreTests.swift` | Audit log storage and retrieval |
| `ModerationWorkspaceStoreTests.swift` | Snapshot capture, retention limits |
| `ProfileInspectorViewModelTests.swift` | Profile search, inspect, error states |
| `RelationshipCacheTests.swift` | Relationship caching logic |
| `StringCSVTests.swift` | CSV string parsing |
| `URLBlueskyTests.swift` | Bluesky URL helpers |
| `ViewModelTests.swift` | Combined test class for ListsViewModel + ProfileInspectorViewModel + ListDetailViewModel (197 lines) |
| `WorkspacePreferencesStoreTests.swift` | Saved/recent searches, persistence, deduplication (131 lines) |

**UI Tests:** 1 file at `UITests/BlueskyModerationUITests/BlueskyModerationUITests.swift` (51 lines)
- Tests: app launch, tab bar existence/navigation, settings screen, info screen segments

## Test Structure

**Suite Organization:**
```swift
@testable import BlueskyModeration
import XCTest

@MainActor
final class SomeTests: XCTestCase {
    private var sut: SomeType!

    override func setUp() { ... }       // sync setUp
    override func setUp() async throws { ... }  // async setUp
    override func tearDown() { ... }    // cleanup

    func testFeature() { ... }          // sync test
    func testAsyncFeature() async { ... }      // async test
    func testThrowingFeature() async throws { ... }  // throwing async test
}
```

**Patterns:**
- `@MainActor` on test class when testing `@MainActor` types
- `override func setUp()` or `override func setUp() async throws` for initialization
- `override func tearDown()` for cleanup (nil-ing out properties, clearing mock state)
- Test method naming: `test{Feature}{Scenario}` in snakeCase (e.g., `testInitialStateIsEmpty`, `testLoadWithNilAccountSetsNoError`)
- Tests use `XCTAssertEqual`, `XCTAssertTrue`, `XCTAssertFalse`, `XCTAssertNil`, `XCTAssertNotNil`, `XCTFail`

## Mocking Patterns

**No mocking framework** — all mocks are hand-written.

**Mock types** (defined across test files):

| Mock | Protocols | Location |
|------|-----------|----------|
| `MockKeychain` | `KeychainServicing` | `TestHelpers.swift:50-64` |
| `MockKeychainService` | `KeychainServicing` | `AccountStoreTests.swift:50-64` |
| `MockSessionService` | `BlueskySessionServicing` | `TestHelpers.swift:67-118` |
| `MockRequestExecutor` | `BlueskyRequestExecuting` | `TestHelpers.swift:120-146` |
| `MockURLProtocol` | `URLProtocol` subclass | `TestHelpers.swift:150-176` |
| `MockAuthenticatingClient` | `BlueskyAuthenticating` | `AccountStoreTests.swift:67-81` |
| `MockLiveBlueskyClient2` | Subclass of `LiveBlueskyClient` | `ListMembersControllerTests.swift:134-145` |
| `MockImportClient` | `BlueskyProfileInspecting` | `ListImportControllerTests.swift` (inline) |

**Mock patterns:**
- Inline mock types defined at bottom of test file (private)
- Shared mocks in `TestHelpers.swift`
- Closures for configurable behavior: `onSend`, `onAuthenticatedRequest`, `shouldFailAuth`, `requestHandler`
- `MockURLProtocol` intercepts all URL requests in an ephemeral session — the standard pattern for HTTP-level testing

**Example MockRequestExecutor pattern:**
```swift
struct MockRequestExecutor: BlueskyRequestExecuting {
    var onSend: (@Sendable (String, String, [URLQueryItem], Any?, String?, URL?) async throws -> Any)?

    func send<Response: Decodable, Body: Encodable>(...) async throws -> Response {
        if let onSend { return try await onSend(...) as! Response }
        throw BlueskyAPIError.invalidResponse
    }
}
```

## Factory/Test Data Helpers

**All defined in `TestHelpers.swift:4-48`:**

```swift
func makeAccount(handle:, did:) -> AppAccount
func makeActor(did:, handle:, displayName:) -> BlueskyActor
func makeMember(did:, handle:, recordURI:) -> BlueskyListMember
func makeList(id:, name:, kind:, memberCount:) -> BlueskyList
func makeProfile(did:, handle:, displayName:, followersCount:, followsCount:) -> BlueskyProfile
```

And an XCTestCase extension for session creation:
```swift
extension XCTestCase {
    func makeSession(for handle:) -> BlueskySession
}
```

**Helper types:** `EmptyDecodable` (`TestHelpers.swift:148`) for tests needing a generic `Decodable`.

## Coverage Assessment

### What IS Tested (good coverage):

**Services:**
- `BlueskyRequestExecutor` — ✅ HTTP codes, auth headers, encoding, error mapping
- `BlueskySessionService` (via `MockSessionService`) — ✅ delegate behavior
- `BlueskyListService` — ✅ fetch, pagination, decode
- `BlueskyProfileService` — ✅ profile fetch
- `LiveBlueskyClient` — ✅ PLC audit, delegate forwarding, blocklist
- `KeychainService` — ✅ CRUD operations
- `RelationshipCache` — ✅

**Stores:**
- `AccountStore` — ✅ add/remove, persistence, keychain
- `ActionQueueStore` — ✅ enqueue, cancel, retry
- `ModerationWorkspaceStore` — ✅ snapshots, retention
- `ModerationAuditStore` — ✅
- `WorkspacePreferencesStore` — ✅ searches, persistence, deduplication

**Controllers:**
- `ListMembersController` — ✅ pagination, deduplication
- `ListDiffController` — ✅
- `ListImportController` — ✅ classification (ready, already, duplicate, unresolved)
- `ListBatchController` — ✅ batch operations, error handling

**View Models:**
- `ListsViewModel` — ✅ list management, cache
- `ProfileInspectorViewModel` — ✅ search, inspect, validation
- `ListDetailViewModel` — ✅ state initialization, selection

**Models/Utilities:**
- `LoadableState` — ✅ all state transitions (idle, loading, loaded, failed)
- `AppError` — ✅ all error categories, conversion from all error types
- Bluesky API DTOs — ✅ JSON decoding for all response types
- `String+CSV` — ✅
- `URL+Bluesky` — ✅

### What is NOT Tested (gaps):

**High Priority:**
- `LiveBlueskyClient` list operations (fetch, add, remove, create, delete, update) — only authentication/blocklist are tested
- `ListMergeController` — no test file exists
- `ListDetailViewModel+Bulk.swift`, `ListDetailViewModel+Data.swift`, `ListDetailViewModel+Search.swift` — no dedicated tests for bulk operations, data loading, or search
- Offline/error recovery paths in stores

**Medium Priority:**
- `DashboardCache.swift` — caching logic untested
- `AppLockManager.swift` — lock/unlock state machine
- `iCloudAccountSync` — cloud sync logic
- `NetworkMonitor.swift` — connectivity monitoring
- `ModerationRuleStore.swift` — rule management
- `ActionPresetStore.swift` — preset management

**Low Priority / Views:**
- No SwiftUI view unit tests (XCTest cannot render SwiftUI views)
- UI tests only cover tab bar existence and navigation (minimal)
- No preview snapshot tests
- No integration tests combining multiple services

### Untested Files (no corresponding test file):
- `ListMergeController.swift`
- `DashboardCache.swift`
- `AppLockManager.swift`
- `iCloudAccountSync.swift`
- `NetworkMonitor.swift`
- `ModerationRuleStore.swift`
- `ActionPresetStore.swift`
- `TrendDetectionView.swift` + `ListTemplatesView.swift`
- `BulkProfileLookupViewModel.swift`
- `ReportGeneratorView.swift`
- `FollowerDiffView.swift` + `NetworkGraphView.swift`
- All component views in `Sources/Shared/Components/`
- All view files in `Sources/Features/`

## Test Quality Observations

**Strengths:**
- Mocks are minimal and focused (only override what's needed)
- Factory helpers reduce test boilerplate significantly
- Test isolation via `UserDefaults(suiteName:)` with unique UUID names
- Async test methods used consistently (`async throws` or `async`)
- `tearDown` properly clears mock state (e.g., `MockURLProtocol.requestHandler = nil`)
- Edge cases covered: empty arrays, deduplication, duplicates, whitespace trimming, maximum limits

**Weaknesses:**
- Some mocks use `as!` force casting (`MockRequestExecutor`, `MockSessionService`) — will crash on type mismatch
- `Nonisolated(unsafe)` on `MockURLProtocol.requestHandler` — concurrency-safe but not ideal
- Test files sometimes combined (e.g., `ViewModelTests.swift` tests 3 different view models)
- No performance tests, no stress tests for large datasets
- No snapshot testing for UI regression

---

*Testing analysis: 2026-05-12*
