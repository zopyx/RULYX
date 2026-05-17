# Codebase Concerns

**Analysis Date:** 2026-05-12

## Security Concerns

### CRITICAL: PinningDelegate Accepts Any Certificate for bsky.social
- **Issue:** `PinningDelegate` at `Sources/Domain/Services/BlueskyRequestExecutor.swift:115-131` accepts ANY server certificate for `bsky.social` without validating a pinned public key. The `URLCredential(trust: serverTrust)` pattern trusts all certificates from the server's chain, which defeats TLS pinning.
- **Files:** `Sources/Domain/Services/BlueskyRequestExecutor.swift:115-131`
- **Impact:** Man-in-the-middle (MITM) attacks against bsky.social API calls are possible. An attacker with a valid CA-issued certificate (or who compromises a CA trusted by the device) can intercept all Bluesky API traffic including JWT tokens.
- **Fix approach:** Extract and validate the server's public key against a hardcoded fingerprint. Use a library like `TrustKit` or implement manual `SecTrustEvaluate` with pinned SPKI hashes.

### HIGH: Test Credentials in `.env` File Read by Live Tests
- **Issue:** `LiveAuthenticationTests.swift` at `Tests/BlueskyModerationTests/LiveAuthenticationTests.swift:67-93` reads `BLUESKY_TEST_USER` and `BLUESKY_TEST_PASSWORD` from a `.env` file at the repository root. The `.env` file is present in the project directory.
- **Files:** `Tests/BlueskyModerationTests/LiveAuthenticationTests.swift:67-93`, `.env`
- **Impact:** Test credentials could be accidentally committed to git or leaked via CI logs. The `.env` file exists on disk with real credentials.
- **Fix approach:** Use iOS keychain or CI environment variables only. Add `.env` to `.gitignore` (verify it is already). Never store credentials in files accessible to the repo.

### HIGH: Hardcoded English Error Messages in AccountStore
- **Issue:** `AccountStore.swift` uses hardcoded English strings for error messages that are NOT passed through `loc()` localization:
  - Line 60: `"Handle and app password are required."`
  - Line 65: `"This account already exists."`
  - Line 102: `"Failed to delete secure credentials."`
  - Line 201: `"Failed to restore saved accounts."`
  - Line 211: `"Failed to save accounts."`
- **Files:** `Sources/Domain/Services/AccountStore.swift:60,65,102,201,211`
- **Impact:** Non-English users see English error messages. These are user-facing strings sent as `errorMessage` to the UI.
- **Fix approach:** Add localization keys for each message and use `loc()` instead of hardcoded strings.

### MEDIUM: AppLockManager Authentication Reason Not Localized
- **Issue:** `AppLockManager.swift:87,91` has hardcoded English string `"Authenticate to access your accounts and moderation data."` passed as `localizedReason` to `LAContext.evaluatePolicy()`.
- **Files:** `Sources/Shared/Support/AppLockManager.swift:87,91`
- **Impact:** System biometric dialog always shows English text regardless of device language.
- **Fix approach:** Localize this string and pass the localized version. Note: LAContext localizations require `Localized.strings` files, not the app's JSON-based i18n.

### MEDIUM: In-Memory Session Cache Holds JWT Tokens
- **Issue:** `BlueskySessionService.swift:22` stores `BlueskySession` objects (which contain `accessJWT` and `refreshJWT`) in an in-memory `cachedSessions` dictionary. While these are also stored in the keychain, the in-memory cache is not protected by the app lock mechanism.
- **Files:** `Sources/Domain/Services/BlueskySessionService.swift:22`
- **Impact:** If device memory is compromised (debugger attached, memory dump), JWT tokens could be extracted from the in-memory cache.
- **Fix approach:** Clear cached sessions when the app locks. Consider using the `SecAccessControl` with biometry constraint on the keychain items.

## Maintainability

### HIGH: SwiftLint Disables 32 Critical Rules
- **Issue:** `.swiftlint.yml` disables `force_cast`, `force_try`, `force_unwrapping`, `todo`, `function_body_length`, `file_length`, `type_body_length`, `cyclomatic_complexity`, `line_length`, and more. This masks code quality issues.
- **Files:** `.swiftlint.yml:8-32`
- **Impact:** Force unwraps, TODOs, long functions, and complex methods go undetected during CI. Many issues that SwiftLint would catch are invisible to automated review.
- **Fix approach:** Re-enable `force_unwrapping`, `todo`, `force_cast` at minimum. Audit existing violations once.

### HIGH: LiveBlueskyClient is 927 Lines — Single File Monolith
- **Issue:** `Sources/Domain/Services/LiveBlueskyClient.swift` at 927 lines handles authentication, list CRUD, actor search, profile inspection, Clearsky integration, followers/following, PLC audit, and DID resolution in a single class.
- **Files:** `Sources/Domain/Services/LiveBlueskyClient.swift` (927 lines)
- **Impact:** Hard to test, hard to maintain. Changes to one area risk breaking unrelated functionality. Makes onboarding harder.
- **Fix approach:** Split into focused services: `ListService`, `ProfileService`, `AuthService`, `ClearskyService`, `SocialGraphService`.

### HIGH: Massive PreviewBlueskyClient with Duplicate Logic (428 lines)
- **Issue:** `Sources/Domain/Services/PreviewBlueskyClient.swift` contains 428 lines of mock/preview data with substantial duplicated boilerplate replicating the real `LiveBlueskyClient` interface.
- **Files:** `Sources/Domain/Services/PreviewBlueskyClient.swift` (428 lines)
- **Impact:** Duplication between mock and real implementations. Changes to the real service interface require parallel updates to the preview client. High maintenance burden.
- **Fix approach:** Use a protocol-based approach with a lightweight mock generator or use Swift's `#if DEBUG` for preview data within the real service.

### MEDIUM: ListDetailViewModel Has 32 @Published Properties
- **Issue:** `Sources/Features/Lists/ListDetailViewModel.swift:5-32` declares 32 `@Published` properties in a single class. The view model logic is spread across `ListDetailViewModel.swift`, `ListDetailViewModel+Data.swift`, `ListDetailViewModel+Bulk.swift`, `ListDetailViewModel+Search.swift` (4 files).
- **Files:** `Sources/Features/Lists/ListDetailViewModel.swift`, `Sources/Features/Lists/ListDetailViewModel+Data.swift`, `Sources/Features/Lists/ListDetailViewModel+Bulk.swift`, `Sources/Features/Lists/ListDetailViewModel+Search.swift`
- **Impact:** High cognitive load. Hard to reason about state changes, what mutates what, and possible invalid state combinations.
- **Fix approach:** Split into focused sub-viewmodels or feature controllers, e.g., `SearchController`, `BulkActionController`, `MemberListController`.

### MEDIUM: InfoView Feature Descriptions Hardcoded in English
- **Issue:** `Sources/App/InfoView.swift:164-202` feature cards contain hardcoded English descriptions in arrays of strings. These are NOT localized.
- **Files:** `Sources/App/InfoView.swift:164-202`
- **Impact:** The "Features" tab and overview section display English descriptions regardless of user's language preference.
- **Fix approach:** Add localization keys for all feature description strings and use `loc()`.

## Localization Issues

### HIGH: ModerationRulesView Displays Raw Enum Values as UI Text
- **Issue:** `Sources/Features/Lists/ModerationRulesView.swift:51,58` uses `Text(t.rawValue)` and `Text(a.rawValue)` to display trigger/action options. Raw values are English strings (e.g., "handleContains", "hasLabel") and will show as-is to users.
- **Files:** `Sources/Features/Lists/ModerationRulesView.swift:16,51,58`
- **Impact:** Users see developer-internal enum raw values ("handleContains" → "hasLabel") instead of localized display strings.
- **Fix approach:** Add `localizedTitle` computed properties on `ModerationRule.Trigger` and `ModerationRule.Action` that return localized strings.

### MEDIUM: List Kind Title Hardcoded in English
- **Issue:** `BlueskyList.Kind.title` at `Sources/Domain/Models/BlueskyList.swift:9-14` returns hardcoded English strings `"Moderation Lists"` and `"Lists"` without localization. This title is used in list headers across the UI.
- **Files:** `Sources/Domain/Models/BlueskyList.swift:9-14`
- **Impact:** List type labels always show in English.
- **Fix approach:** Use `loc("lists.moderation_lists")` and `loc("lists.lists")` instead.

### LOW: AppLockManager.biometricLabel Hardcoded
- **Issue:** `AppLockManager.swift:47-50` returns hardcoded `"Touch ID"`, `"Face ID"`, `"Biometrics"`. These values are used in Settings UI via `settings.biometric_lock` key replacement `{biometric}`.
- **Files:** `Sources/Shared/Support/AppLockManager.swift:47-50`
- **Impact:** Biometric type labels always appear in English strings embedded in otherwise localized text.
- **Fix approach:** Localize via `loc("biometrics.face_id")`, `loc("biometrics.touch_id")`, etc.

## Reliability

### MEDIUM: TrendDetectionView Silently Swallows Errors
- **Issue:** `Sources/Features/Lists/TrendDetectionView.swift:66` catches all errors with an empty `catch` block and only a comment `// Silent fail — data just won't load`. No user feedback, no logging.
- **Files:** `Sources/Features/Lists/TrendDetectionView.swift:66`
- **Impact:** Users see an empty loading state with no indication of failure. Debugging production issues is impossible.
- **Fix approach:** Log the error via `AppLogger.moderation.error(...)` and show a user-friendly error state instead of empty.

### MEDIUM: NetworkGraphView Fallback to Empty String for DID Comparison
- **Issue:** `Sources/Features/Profile/NetworkGraphView.swift:28,30,32` uses `accountB?.did ?? ""` and `accountA?.did ?? ""` for DID comparison checks. If `accountA` or `accountB` is nil, DIDs compare against empty string which could produce false matches.
- **Files:** `Sources/Features/Profile/NetworkGraphView.swift:28-33`
- **Impact:** If both accounts are nil, `aFollowsB` returns `aFollowing.contains("")` which is always false but the state is misleading. This is guarded by the `analyze()` function checking both accounts, but computed properties are still evaluated eagerly in the view body.
- **Fix approach:** Make `aFollowsB` and `bFollowsA` optional, and only evaluate when both accounts are non-nil.

### MEDIUM: URL(string: "...")! Force Unwraps Throughout Codebase
- **Issue:** 12 instances of `URL(string: "...")!` that will crash if the URL string is invalid:
  - `Sources/Domain/Services/LiveBlueskyClient.swift:37` — `URL(string: "https://bsky.social")!`
  - `Sources/Domain/Services/URL+Bluesky.swift:4` — `URL(string: "https://bsky.social")!`
  - `Sources/App/InfoView.swift:102,213,219,225,240,246` — Various hardcoded URLs
  - `Sources/Features/Accounts/AddAccountView.swift:14,15,16` — Provider URLs
  - `Sources/Domain/Services/PreviewBlueskyClient.swift:20` — Test URL
- **Files:** Multiple files (see above)
- **Impact:** If a URL string is ever invalidated by code changes or external input variation, the app crashes with a force-unwrap fatal error.
- **Fix approach:** Use `guard let url = URL(string: ...)` with appropriate error handling. For constant URLs, consider `URL(string: ...)!` acceptable but document as safe. For dynamic URLs (like `AddAccountView`), never force unwrap.

### LOW: Cache Files Not Excluded from iCloud Backup
- **Issue:** `DashboardCache.swift` and `RelationshipCache.swift` write JSON files to the caches directory but do not set `isExcludedFromBackup` on the directory or files.
- **Files:** `Sources/Domain/Services/DashboardCache.swift`, `Sources/Domain/Services/RelationshipCache.swift`
- **Impact:** Cached data may be included in iCloud backups unnecessarily, consuming user's storage quota. Not a critical issue since the data is small.
- **Fix approach:** Set `cachesDirectory.setExcludedFromBackup(true)` on creation.

## Performance

### LOW: Repeated ISO8601DateFormatter Creations
- **Issue:** `LiveBlueskyClient.swift:257,323,386` creates a new `ISO8601DateFormatter()` instance each time a record is created (add, update, delete list operations). This formatter is expensive to create.
- **Files:** `Sources/Domain/Services/LiveBlueskyClient.swift:257,323,386`
- **Impact:** Minor performance overhead on bulk operations. Formatter creation involves locale loading and pattern compilation.
- **Fix approach:** Use a static `ISO8601DateFormatter` singleton or lazy property.

### LOW: `main.swift` Not Present but WidgetExtension Exists
- **Issue:** The project has a `WidgetExtension/` directory with a widget target, but no explicit entry point pattern analysis was possible. The widget shares `UserDefaults.standard` via `App Groups` which requires specific entitlement configuration in `project.yml`.
- **Files:** `WidgetExtension/RulyxWidget.swift:27`, `project.yml`
- **Impact:** Widget data sharing via `UserDefaults.standard` (not app-group) means widget and app may not share data correctly.
- **Fix approach:** Use `UserDefaults(suiteName: "group.com.ajung.BlueskyModeration")` for widget data sharing.

## Concurrency / Swift 6

### MEDIUM: PinningDelegate Not @MainActor
- **Issue:** `PinningDelegate` at `Sources/Domain/Services/BlueskyRequestExecutor.swift:115` is a `URLSessionDelegate` conforming to `NSObjectProtocol` but is NOT annotated with `@MainActor`. It's instantiated via `URLSession(configuration: .ephemeral, delegate: PinningDelegate(), delegateQueue: nil)` where `nil` means a background serial queue. Swift 6 strict concurrency will flag this.
- **Files:** `Sources/Domain/Services/BlueskyRequestExecutor.swift:115-131`
- **Impact:** Potential threading violations. The delegate callback runs on a background queue but modifies no shared state, so it's functionally correct but may produce Swift 6 warnings.
- **Fix approach:** Either mark `@MainActor` on the entire class, or use `nonisolated func urlSession(...)` with explicit Sendable conformance.

### LOW: SearchToken @MainActor + Sendable Mismatch
- **Issue:** `SearchToken` at `Sources/Shared/Support/SearchToken.swift:6-7` is both `@MainActor` and `Sendable`. In Swift 6, a `@MainActor` class cannot conform to `Sendable` since its methods can only be called from the main actor.
- **Files:** `Sources/Shared/Support/SearchToken.swift:6-7`
- **Impact:** May produce Swift 6 concurrency warnings. The `id` property is correctly `nonisolated`, so the `Sendable` conformance is safe but may still trigger diagnostics.
- **Fix approach:** Remove `@MainActor` annotation and rely on `nonisolated let id` pattern, or remove `Sendable` and pass tokens within `@MainActor` context only.

### LOW: Task { @MainActor in } Nested Pattern
- **Issue:** Multiple files use `Task { @MainActor [weak self] in ... }` or `Task { @MainActor in ... }` pattern (e.g., `AccountStore.swift:44`, `ActionQueueStore.swift:94`, `iCloudAccountSync.swift:24`). This creates a nested `Task` context on the main actor, which is redundant when the enclosing method is already `@MainActor`.
- **Files:** `Sources/Domain/Services/AccountStore.swift:44`, `Sources/Domain/Services/ActionQueueStore.swift:94`, `Sources/Shared/Support/iCloudAccountSync.swift:24`
- **Impact:** Unnecessary task nesting creates extra allocation overhead per invocation. May also cause subtle issues with `Task.isCancelled` propagation.
- **Fix approach:** Use `MainActor.run { ... }` or remove the inner `Task` wrapper when already on `@MainActor`.

## Test Coverage Gaps

### HIGH: AccountStore Has Only 2 Tests
- **Issue:** `AccountStoreTests.swift` contains only 2 tests: one for adding an account and one for session-based loading. Critical methods like `removeAccount`, `setActiveAccount`, `setLabel`, `moveAccount`, `refreshAccountProfiles`, `mergeCloudAccounts` have zero tests.
- **Files:** `Tests/BlueskyModerationTests/AccountStoreTests.swift` (2 tests)
- **Impact:** Account management is a core security-sensitive feature. Bugs in credential deletion, cloud sync merging, or account switching could lead to data loss or credential leaks.
- **Priority:** HIGH

### HIGH: Zero Tests for Views (UI Tests Empty)
- **Issue:** `UITests/BlueskyModerationUITests/BlueskyModerationUITests.swift` at 0 test methods. No snapshot tests, no UI interaction tests exist.
- **Files:** `UITests/BlueskyModerationUITests/BlueskyModerationUITests.swift`
- **Impact:** UI regressions are undetectable in CI. Critical user flows (account add, list management, bulk operations) have no automated validation.
- **Priority:** HIGH

### MEDIUM: ProfileInspectorViewModel Has Only 5 Tests
- **Issue:** `ProfileInspectorViewModelTests.swift` has 5 tests. The view model handles search, inspection, error states, and credential validation. Coverage is minimal.
- **Files:** `Tests/BlueskyModerationTests/ProfileInspectorViewModelTests.swift`
- **Impact:** Profile inspection is a core feature (search, inspect, label display, moderation actions). Missing tests for error handling, empty states, and edge cases.

### MEDIUM: ListDetailViewModelTests Missing Bulk Operation Tests
- **Issue:** `ListDetailViewModelTests.swift` has 24 tests but does not test `bulkAddSelectedActors`, `bulkRemoveSelectedMembers`, `bulkBlockSelectedMembers`, `retryFailures`, `performActorBatch` or any of the bulk operation methods.
- **Files:** `Tests/BlueskyModerationTests/ListDetailViewModelTests.swift`, `Sources/Features/Lists/ListDetailViewModel+Bulk.swift`
- **Impact:** Bulk operations are the core feature of the app. No test coverage for multi-step operations, progress tracking, or error recovery.

### MEDIUM: NetworkGraphView, TrendDetectionView, FollowerDiffView Untested
- **Issue:** No test files exist for `NetworkGraphView`, `TrendDetectionView`, `FollowerDiffView`, or their view models/logic.
- **Files:** `Sources/Features/Profile/NetworkGraphView.swift`, `Sources/Features/Lists/TrendDetectionView.swift`, `Sources/Features/Profile/FollowerDiffView.swift`
- **Impact:** These features handle network analysis, trend detection, and follower diffing — all logic-heavy with potential edge cases.

### LOW: ModerationWorkspaceStore Has Only 3 Tests
- **Issue:** `ModerationWorkspaceStoreTests.swift` has only 3 tests for a store that manages saved searches, recent searches, operation logs, and queued actions.
- **Files:** `Tests/BlueskyModerationTests/ModerationWorkspaceStoreTests.swift`
- **Impact:** Operations tracking and search history persistence are untested.

## Tech Debt

### MEDIUM: Duplicate BlueskyProfileService/BlueskyListService Wrappers
- **Issue:** `BlueskyProfileService` (408 lines) and `BlueskyListService` (286 lines) are thin wrappers around `LiveBlueskyClient` that duplicate the API. They add an unnecessary abstraction layer, increasing maintenance burden without clear benefit.
- **Files:** `Sources/Domain/Services/BlueskyProfileService.swift`, `Sources/Domain/Services/BlueskyListService.swift`, `Sources/Domain/Services/BlueskyProfileInspecting.swift`, `Sources/Domain/Services/BlueskyListServicing.swift`
- **Impact:** Any API change requires updating the service, the protocol, and `LiveBlueskyClient`. The preview client must also mirror these changes.
- **Fix approach:** Consider collapsing into `LiveBlueskyClient` directly as the single service provider, using the already-existing protocols.

### MEDIUM: Inconsistent DI Pattern — Some Services Use .shared, Others Use EnvironmentObject
- **Issue:** `LocalizationManager.shared` (singleton) and `AppLockManager.shared` (singleton) are accessed via `.shared` directly. Other services are injected via `@EnvironmentObject` through `AppDependencies`. This mixed approach makes testing harder for singleton-dependent code.
- **Files:** `Sources/Shared/Localizations/LocalizationManager.swift:5`, `Sources/Shared/Support/AppLockManager.swift:6`, `Sources/App/AppDependencies.swift`, `Sources/App/BlueskyModerationApp.swift:6`
- **Impact:** Singletons are hard to mock in tests. `AppLockManager.shared` and `LocalizationManager.shared` cannot be replaced in unit tests without side effects.
- **Fix approach:** Standardize on environment object injection for all services. Remove singleton accessors.

### MEDIUM: ActionQueueStore Stores @Sendable Closure That Captures State
- **Issue:** `ActionQueueStore.swift:15` stores `let action: @Sendable (BlueskyActor) async throws -> Void` as part of `QueuedAction`. This closure is `@Sendable`-annotated but the `QueuedAction` struct also contains `operation` which is an enum. The `action` closure may capture `@MainActor`-bound state, creating potential Sendable violations.
- **Files:** `Sources/Domain/Services/ActionQueueStore.swift:9-33`
- **Impact:** Swift 6 strict concurrency checking may flag this. Captured `@MainActor` objects in `@Sendable` closures can cause data races if invoked off the main actor.

### LOW: `String?.none` Used as No-Body Sentry for Void Body
- **Issue:** `BlueskyRequestExecutor.swift:108` and `BlueskySessionService.swift:181` pass `body: String?.none` to the generic `send<Response: Decodable, Body: Encodable>` overload when there is no request body. This typealias trick is non-obvious.
- **Files:** `Sources/Domain/Services/BlueskyRequestExecutor.swift:108`, `Sources/Domain/Services/BlueskySessionService.swift:181`
- **Impact:** Readability issue. Future maintainers may not immediately understand the intent. A dedicated `NoBody` type or a separate overload without the `body` parameter would be clearer.
- **Fix approach:** Add a `send<Response>(...)` overload (without body parameter) as the canonical no-body method, and keep the generic `send<Response, Body>(...)` for requests with body.

## Dependency Risks

### LOW: No Explicit Dependency Pinning in project.yml
- **Issue:** The `project.yml` file does not show any Swift Package Manager dependencies being managed through xcodegen. Reliance on SPM package resolution without explicit version pinning in the project config could lead to unexpected upstream changes.
- **Files:** `project.yml`
- **Impact:** Builds may break if SPM packages are updated without explicit version constraints. Not currently a problem since SPM dependencies weren't detected in the project file snippet.
- **Fix approach:** Document all external dependencies with version constraints in the project.yml or Package.swift.

---

*Concerns audit: 2026-05-12*
