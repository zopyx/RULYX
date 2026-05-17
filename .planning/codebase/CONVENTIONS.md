# Coding Conventions

**Analysis Date:** 2026-05-12

## Swift Version & Language Features

**Swift 6.0** enforced via `.swift-version` (line 1) and `project.yml` (`SWIFT_VERSION: "6.0"`, line 10).

**Strict Concurrency Checking** enabled by default in Swift 6. The codebase uses:
- `@MainActor` on all view models, stores, services, and protocols
- `nonisolated(unsafe)` on static test mock state (e.g., `MockURLProtocol.requestHandler` at `TestHelpers.swift:151`)
- `Sendable` used explicitly on `LoadableState<Value: Sendable>` generic constraint (`LoadableState.swift:3`)
- Protocols explicitly annotated `Sendable` (e.g., `BlueskyRequestExecuting: Sendable` at `BlueskyRequestExecutor.swift:3`)
- Most model structs (`BlueskyList`, `BlueskyProfile`, `BlueskyActor`, `AppAccount`) conform to `Codable`/`Hashable` which implies `Sendable` in Swift 6, but do NOT have explicit `Sendable` conformances

## Code Formatting

**Tool:** `swiftformat` — configuration at `.swiftformat` (8 lines)

**Settings:**
| Option | Value |
|--------|-------|
| `--indent` | 4 spaces |
| `--stripunusedargs` | `always` |
| `--semicolons` | `never` |
| `--trimwhitespace` | `always` |
| `--wraparguments` | `before-first` |
| `--wrapparameters` | `before-first` |
| `--wrapcollections` | `before-first` |

**Run command:**
```bash
swiftformat Sources Tests     # auto-format
swiftformat --lint .          # check only
```

## Linting

**Tool:** `swiftlint` — configuration at `.swiftlint.yml` (32 lines)

**Scope:** Sources and Tests included; `.build` and `DerivedData` excluded.

**Disabled Rules (27 rules disabled):**
- `closure_body_length`, `closure_spacing`, `cyclomatic_complexity`, `file_length`, `file_name`
- `force_cast`, `force_try`, `force_unwrapping` — **force unwrapping is permitted**
- `function_body_length`, `function_parameter_count`, `identifier_name`, `large_tuple`
- `line_length` — **no line length limit**
- `missing_docs` — **documentation is not required**
- `nesting`, `nslocalizedstring_require_bundle`, `todo`
- `trailing_comma`, `type_body_length`, `type_name`
- `unused_import`, `unused_optional_binding`, `vertical_parameter_alignment`, `vertical_whitespace`

**Net effect:** Very permissive linting — enables rapid development with minimal lint noise.

**Run command:**
```bash
swiftlint
```

## Naming Conventions

**Files:**
- Swift files: PascalCase matching the primary type name (e.g., `AppAccount.swift`, `BlueskyListServicing.swift`)
- Test files: `{TypeName}Tests.swift` (e.g., `AccountStoreTests.swift`, `LoadableStateTests.swift`)

**Types:**
- Classes/Structs/Enums: `PascalCase` (e.g., `BlueskyList`, `AppErrorCategory`, `ListMembersController`)
- Protocols: `{Noun}Servicing` suffix for service protocols (e.g., `BlueskyListServicing`, `KeychainServicing`, `BlueskySessionServicing`)
- Protocols: `{Noun}Inspecting` suffix for inspection protocols (e.g., `BlueskyProfileInspecting`)
- Protocols: `{Noun}ing` suffix for authentication protocol (e.g., `BlueskyAuthenticating`)

**Properties & Functions:**
- `camelCase` (e.g., `memberCount`, `accessJWT`, `fetchListMembersPage`)
- Boolean properties use `is` prefix: `isLoading`, `isLoaded`, `isMember`, `hasMore`, `isNew`
- Private stored properties with `private let`/`private var`

**Enums:**
- Cases: `lowerCamelCase` (e.g., `.moderation`, `.regular`, `.authentication`, `.cancellation`)
- Associated values use parameter labels: `case server(String)`

**Generics:**
- Single letter: `Value`, `Response`, `Body`
- Descriptive in protocol declarations: `Response: Decodable, Body: Encodable`

## Import Organization

**Pattern:**
```swift
import Foundation        // or SwiftUI, XCTest, Security, Charts, os
```

- Single import per framework (one line per framework)
- No blank lines between imports
- In test files: `@testable import BlueskyModeration` first, then `import XCTest`
- Imports at file top only (no conditional imports observed)

**Frameworks used across the codebase:**
- `Foundation` — all files
- `SwiftUI` — view files, `LocalizationManager.swift`, `LocalizedText.swift`
- `XCTest` — all test files
- `Security` — `KeychainService.swift`
- `os` — `AppLogger.swift`
- `Charts` — `DashboardView.swift`

## Error Handling Conventions

**Two-tier error hierarchy:**

1. **Domain-specific:** `BlueskyAPIError` (`BlueskyAPIError.swift:3-23`)
   - Cases: `invalidURL`, `invalidResponse`, `unauthorized`, `missingCredentials`, `server(String)`
   - Conforms to `LocalizedError`

2. **Normalized:** `AppError` (`AppError.swift:13-88`)
   - Wraps `BlueskyAPIError`, `DecodingError`, `URLError`, `CancellationError`, and unknown errors
   - Has `category: AppErrorCategory` (enum: `.authentication`, `.network`, `.decoding`, `.validation`, `.server`, `.cancellation`, `.unknown`)
   - Factory: `AppError.from(_ error: Error) -> AppError`
   - Helper: `AppError.userMessage(from:) -> String`
   - Conforms to `LocalizedError` and `Equatable`

**Error handling patterns:**
- Services throw domain errors (`BlueskyAPIError`)
- View models catch and convert to user-facing messages via `AppError.userMessage(from:)`
- `errorMessage: String?` published property pattern for view-level display
- Guard-early pattern for input validation: `guard !trimmedHandle.isEmpty else { errorMessage = "..."; return false }`

## Concurrency Patterns

**@MainActor usage:**
- All view models: `@MainActor final class ...: ObservableObject`
- All stores: `@MainActor final class ...: ObservableObject`
- All service protocols annotated `@MainActor` (except `BlueskyRequestExecuting` which is `Sendable`)
- `LiveBlueskyClient` is a `@MainActor class`
- Mock implementations match the same isolation level

**Async patterns:**
- `async throws` on all service methods
- `async` on view model methods
- `Task { @MainActor [weak self] in ... }` for notification-based callbacks (`AccountStore.swift:44`)
- `withThrowingTaskGroup` for parallel batch operations (`LiveBlueskyClient.swift:619`)
- `async let` for concurrent requests (`LiveBlueskyClient.swift:854-882`)
- `defer { isAddingAccount = false }` for state cleanup

**Actor isolation gaps (notable):**
- `MockURLProtocol.requestHandler` uses `nonisolated(unsafe)` — safe for tests but a concurrency escape hatch
- Model structs (`BlueskyList`, `BlueskyProfile`, `BlueskyActor`, `AppAccount`) do not explicitly conform to `Sendable` — rely on synthesized conformance from `Codable`/`Hashable`

## Protocol-Oriented Design

**Protocol naming convention:** `{Role}ing` suffix for service protocols:
- `BlueskyListServicing` — list CRUD operations
- `BlueskySessionServicing` — authentication session management
- `BlueskyProfileInspecting` — profile lookup, search, moderation actions
- `BlueskyRequestExecuting` — lower-level HTTP request execution (`Sendable`)
- `BlueskyAuthenticating` — authentication protocol
- `KeychainServicing` — keychain read/write/delete

**Dependency injection** via protocol conformance:
- Services are initialized with protocol-typed dependencies (e.g., `BlueskyRequestExecuting`)
- Tests inject mock conformances (e.g., `MockRequestExecutor`, `MockSessionService`)
- `AppDependencies.swift` creates concrete instances and wires them together

## Logging Conventions

**Framework:** `os.Logger` wrapped in `AppLogger` enum (`AppLogger.swift:4-11`)

**Categories:**
| Logger | Category | Usage |
|--------|----------|-------|
| `AppLogger.search` | `"search"` | Actor search operations |
| `AppLogger.persistence` | `"persistence"` | Data persistence events |
| `AppLogger.moderation` | `"moderation"` | Moderation actions |
| `AppLogger.performance` | `"performance"` | Request timing / API latency |

**Privacy annotations:** `.public` on log values (e.g., `\(path, privacy: .public)`) — note: this may log user handles publicly in system logs

**Usage pattern:** `AppLogger.moderation.error("Failed to refresh profile for \(account.handle, privacy: .public)")`

## Localization / Internationalization

**Function:** `loc(_ key: String) -> String` (global `@MainActor` function at `LocalizationManager.swift:83-85`)

**Implementation:**
- `LocalizationManager` singleton (`LocalizationManager.swift:5`) with `@Published var currentLanguage`
- JSON files for each language in `Sources/Shared/Localizations/`:
  - 16 languages: `en.json`, `de.json`, `fr.json`, `it.json`, `ja.json`, `zh.json`, `es.json`, `pt.json`, `ko.json`, `ru.json`, `ar.json`, `nl.json`, `pl.json`, `tr.json`, `th.json`, `vi.json`
  - Each file: `[String: String]` dictionary (588 keys in `en.json`)
- Fallback chain: current language → English → raw key
- Plural support via `localizedPlural(_:count:)` using `_one`/`_other` key suffixes

**String usage:**
- All user-facing strings in SwiftUI views use `loc("key")` (e.g., `Text(verbatim: loc("dashboard.overview"))`)
- Dynamic strings with interpolation use `loc()` inside `Text(verbatim:)` or string concatenation
- `LText` view struct wraps `LocalizationManager.localized()` for SwiftUI previews
- Extension `View.localizedString(_:)` available as alternative

## Comments & Documentation

**When to comment:** Code is generally self-documenting with minimal comments.

**Observed patterns:**
- `// MARK: - Section Name` for organizing large files (e.g., `LiveBlueskyClient.swift` has `// MARK: - Authentication & Session`, `// MARK: - List Operations`, etc.)
- No JSDoc/TSDoc-style documentation comments (`///`) observed on any public API
- No inline documentation for view model properties or methods
- Test classes use `// MARK: - ListsViewModel` style for test organization

## Common Patterns

**View Model pattern:**
```swift
@MainActor
final class SomeViewModel: ObservableObject {
    @Published private(set) var state = ...
    @Published var errorMessage: String?

    func someAction(using client: LiveBlueskyClient) async {
        isLoading = true
        errorMessage = nil
        do {
            // ... async work ...
        } catch {
            errorMessage = AppError.userMessage(from: error)
        }
        isLoading = false
    }
}
```

**Service pattern:**
```swift
@MainActor
protocol SomeServicing {
    func someMethod(...) async throws -> ReturnType
}

@MainActor
final class SomeService: SomeServicing {
    private let dependency: SomeDependency
    init(dependency: SomeDependency) { ... }
}
```

**Controller pattern** (for complex operations):
- `ListMembersController` — pagination-aware member fetching
- `ListDiffController` — list comparison logic
- `ListImportController` — import/resolve workflow
- `ListBatchController` — batched operations with progress tracking

**Store pattern** (persistence):
- `AccountStore`, `WorkspacePreferencesStore`, `ModerationWorkspaceStore`, `ModerationAuditStore`, `ActionQueueStore`
- `UserDefaults` for lightweight persistence (with `defaults: UserDefaults` constructor injection for testability)
- `KeychainService` for secure credential storage

**Preview/mock pattern:**
- `MockBlueskyListService` and `MockBlueskyProfileService` in `Sources/Domain/Services/Preview/`
- Preview clients simulate async delays via `Task.sleep(for: .milliseconds(...))`
- `preview: Bool` parameter on stores for populating sample data

## Anti-Patterns Observed (Notable)

1. **Hardcoded strings in views** — some views use `loc("key")` correctly but `DashboardView.swift` uses `Text(verbatim: loc("..."))` wrapping unnecessarily
2. **Error messages** — some error messages are hardcoded in English rather than using `loc()` (e.g., `"Select an active account first."` in `ViewModelTests.swift:126`)
3. **Force unwrapping** — permitted and used (e.g., `URL(string: ...)!` in several places, `try!` in tests)
4. **Large files** — `LiveBlueskyClient.swift` is 927 lines; `BlueskySessionService.swift` is 363 lines
5. **Missing explicit Sendable** — most model types rely on synthesized conformance rather than explicit `Sendable` annotation
6. **nonisolated(unsafe) in tests** — `MockURLProtocol.requestHandler` at `TestHelpers.swift:151`

---

*Convention analysis: 2026-05-12*
