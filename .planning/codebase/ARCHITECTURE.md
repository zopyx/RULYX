# Architecture

**Analysis Date:** 2026-05-12

## Pattern Overview

**Overall:** MVVM + Store pattern (SwiftUI + ObservableObject)

**Key Characteristics:**
- Views are pure SwiftUI structs with `@EnvironmentObject` for dependency injection
- ViewModels are `@MainActor` `ObservableObject` classes with `@Published` properties
- Stores are `@MainActor` `ObservableObject` classes that encapsulate domain state and persistence (UserDefaults, Keychain, file cache)
- Controllers are stateless `@MainActor` classes that encapsulate complex business logic (pagination, batch operations, diff/compare, import parsing)
- A single `LiveBlueskyClient` class conforms to multiple service protocols and acts as the unified network-facing facade
- No Coordinator/Router pattern — navigation is handled via `NavigationStack` + `NavigationLink` + `.navigationDestination` + `.sheet()` within views

## Layers

**App Layer:**
- Purpose: App entry point, DI container, root navigation
- Location: `Sources/App/`
- Contains: `BlueskyModerationApp.swift` (lines 1-37), `BlueskyModerationApp+macOS.swift` (lines 1-26), `RootView.swift` (lines 1-115), `AppDependencies.swift` (lines 1-29), `SettingsView.swift` (lines 1-138), `InfoView.swift`
- Depends on: All other layers (wires everything together)
- Used by: SwiftUI runtime

**Feature Layer:**
- Purpose: Feature-specific views, view models, and controllers organized by domain
- Location: `Sources/Features/`
- Sub-directories: `Lists/`, `Profile/`, `Accounts/`
- Contains: SwiftUI Views, ViewModels (`@MainActor ObservableObject`), Controllers (stateless business logic)
- Depends on: Domain/Services layer (protocols), Domain/Models layer, Shared/Components
- Used by: App layer (via RootView tab content)

**Domain/Services Layer:**
- Purpose: Network communication, session management, persistence stores, caching
- Location: `Sources/Domain/Services/`
- Contains: `LiveBlueskyClient` (lines 31-927), `BlueskySessionService` (lines 17-324), `BlueskyRequestExecutor` (lines 1-131), Protocol definitions (`BlueskyListServicing` lines 1-14, `BlueskyProfileInspecting` lines 1-17, `BlueskySessionServicing` lines 1-15), Stores (`AccountStore`, `ModerationWorkspaceStore`, `ModerationAuditStore`, `WorkspacePreferencesStore`, `ActionQueueStore`), Caches (`DashboardCache`, `RelationshipCache`), `KeychainService`
- Depends on: Domain/Models layer
- Used by: Feature layer (ViewModels call service protocols), App layer (DI container creates instances)

**Domain/Models Layer:**
- Purpose: Data models and DTOs
- Location: `Sources/Domain/Models/`
- Contains: `BlueskyActor`, `BlueskyProfile`, `BlueskyList`, `BlueskyListMember`, `AppAccount`, `ProfileMembershipModels`
- Depends on: Foundation only
- Used by: All layers

**Shared Layer:**
- Purpose: Cross-cutting concerns — localization, theme, reusable components, utilities
- Location: `Sources/Shared/`
- Sub-directories: `Components/`, `Support/`, `Theme/`, `Localizations/`
- Contains: Reusable SwiftUI views (`BlueskyActorRow`, `AccountSummaryCard`, `StatePanels`, etc.), `AppError`, `AppLogger`, `LoadableState`, `AppLockManager`, `NetworkMonitor`, color extensions, localization engine
- Depends on: Models layer (for type references)
- Used by: Feature layer (components used in views)

## Data Flow

**Standard Network → Store → View flow:**

1. View triggers action (user taps button, `.task {}`, `.refreshable {}`)
2. View calls `viewModel.someAction()` via `Task { ... }`
3. ViewModel (on `@MainActor`) calls `client.fetchSomething(account:password:)` via `try await`
4. `LiveBlueskyClient` delegates to `BlueskySessionService.performAuthenticatedRequest()` which handles JWT auth, refresh, and re-auth
5. `BlueskyRequestExecutor.send()` makes the actual HTTP call via `URLSession` (lines 36-95 of `BlueskyRequestExecutor.swift`)
6. Response decoded from JSON → Domain Models
7. ViewModel sets `@Published` property (back on MainActor)
8. SwiftUI re-renders the View

**Store persistence flow:**

- `AccountStore` (lines 185-213): `load()`/`persist()` via `UserDefaults` + `KeychainService` for credentials
- `ModerationWorkspaceStore` (lines 15-106): Orchestrates `WorkspacePreferencesStore` + `ModerationAuditStore` + `ActionQueueStore` via Combine subscriptions
- `ModerationAuditStore` (lines 233-243): Persists snapshots and operation logs to `UserDefaults` as JSON
- `DashboardCache` (lines 1-41): File-based cache in `cachesDirectory`, JSON encoded/decoded
- `RelationshipCache` (lines 1-29): File-based cache for follower/following lists

**State Management:**
- Each ViewModel (e.g., `ListsViewModel` lines 4-115) owns a set of `@Published` properties
- Loading state is managed via explicit `@Published var isLoading`, `@Published var errorMessage: String?` pattern
- `LoadableState` enum (lines 1-36) exists but is NOT widely used; most VMs use the loading+error pattern directly
- Stores (`AccountStore`, `ModerationWorkspaceStore`) are `@Published` singletons observable cross-feature
- `WorkspaceTab` selection is stored in `ModerationWorkspaceStore.selectedTab` (line 9) and synced with `WorkspacePreferencesStore`

## Key Abstractions

**Service Protocols (protocol-based abstraction layer):**
- `BlueskyListServicing` (`Sources/Domain/Services/BlueskyListServicing.swift`, lines 1-14): `@MainActor` protocol for list CRUD
- `BlueskyProfileInspecting` (`Sources/Domain/Services/BlueskyProfileInspecting.swift`, lines 1-17): `@MainActor` protocol for profile/actor operations
- `BlueskySessionServicing` (`Sources/Domain/Services/BlueskySessionService.swift`, lines 1-15): Session lifecycle
- `BlueskyRequestExecuting` (`Sources/Domain/Services/BlueskyRequestExecutor.swift`, lines 1-20): `Sendable` protocol for raw HTTP
- `KeychainServicing` (`Sources/Domain/Services/KeychainService.swift`, lines 9-12): Keychain abstraction

**`LiveBlueskyClient` as unified facade:**
- `Sources/Domain/Services/LiveBlueskyClient.swift`, lines 31-927
- Conforms to: `BlueskyAuthenticating`, `BlueskyListServicing`, `BlueskyProfileInspecting`
- Composes `BlueskyRequestExecutor` + `BlueskySessionService`
- Adds non-AT Protocol integrations (Clearsky for blocking data, PLC directory for audit logs, public bsky.app API for profile batches)
- `PreviewBlueskyClient` (lines 1-428) subclasses it for SwiftUI previews with fake data

**Controllers (business logic extracted from ViewModels):**
- `ListMembersController` (lines 1-62): Pagination state for list members, deduplication
- `ListImportController` (lines 1-156): Parses raw text into resolved handles/DIDs, classifies import items
- `ListDiffController` (lines 1-88): List comparison (overlap, onlyInCurrent, onlyInOther)
- `ListBatchController` (lines 1-76): Batch execution with rate limiting, progress callbacks, retry
- All controllers are `@MainActor` classes created by `ListDetailViewModel` (line 34-40)

**`ListDetailViewModel` extensibility pattern:**
- Base class at `ListDetailViewModel.swift` (lines 1-41) declares properties and controller references
- Extensions in separate files for logical grouping:
  - `ListDetailViewModel+Data.swift` (288 lines): Load members, paginate, import, compare, export
  - `ListDetailViewModel+Bulk.swift` (488 lines): Bulk selection and batch operations
  - `ListDetailViewModel+Search.swift`: Search actors

## Entry Points

**iOS Entry Point:**
- Location: `Sources/App/BlueskyModerationApp.swift`, lines 1-37
- Triggers: App launch via `@main`
- Responsibilities: Creates `AppDependencies`, manages lock screen, restores sessions on `.task {}`

**macOS Entry Point:**
- Location: `Sources/App/BlueskyModerationApp+macOS.swift`, lines 1-26
- Platform-guarded with `#if os(macOS)`
- Uses same `AppDependencies` and `RootView`

**Root Navigation:**
- `RootView.swift` lines 1-115: `TabView` with 4 tabs (moderation, settings, info, accounts)
- `ListsView` is the primary tab (moderation)
- `AccountTabView` handles account management
- `SettingsView` has language picker, cache clearing, debug mode, app lock toggle
- `InfoView` is app info/about

## Navigation Architecture

**Pattern:** `NavigationStack` + `NavigationLink` + `.navigationDestination` + `.sheet()`
- `ListsView.swift` line 21: `NavigationStack { ... }`
- `ListsView.swift` lines 70-148: `.navigationDestination(isPresented:)` for profile, followers, following, blocking, blocked-by
- `ListsView.swift` lines 153-190: `NavigationLink { ListDetailView(...) }` for list details
- `ListsView.swift` lines 247-289: `.sheet(isPresented:)` for account picker, bulk lookup, create list, account management
- `ListDetailView.swift` lines 36-68: `.sheet(isPresented:...)` for edit sheet, import sheet, file importer
- `AccountTabView.swift` line 13: `NavigationStack`
- `ProfileInspectorView.swift` line 14: `NavigationStack`

**No deep linking support detected.**

## Concurrency Strategy

**Primary:** `@MainActor` on all ObservableObject classes and service protocols
- All ViewModels: `@MainActor final class ... ObservableObject` (e.g., `ListsViewModel` line 3-4)
- All Stores: `@MainActor final class ... ObservableObject` (e.g., `AccountStore` line 3-4)
- All Services: `@MainActor` on protocols (`BlueskyListServicing` line 3, `BlueskySessionServicing` line 3)
- Controllers: `@MainActor final class` (e.g., `ListMembersController` line 3)
- `BlueskyRequestExecuting` is `Sendable` (line 3) — the only `Sendable` protocol

**Task usage:**
- Views fire `Task { await ... }` blocks for async operations (e.g., `ListsView.swift` line 237-239)
- `.task(id:)` for reactive loading on state changes (e.g., `ListsView.swift` line 290)
- `withThrowingTaskGroup` for parallel profile resolution (e.g., `LiveBlueskyClient.swift` line 619)
- Explicit cancellation checks via `Task.isCancelled` (e.g., `ListBatchController.swift` line 24)

**Actor isolation model:**
- `BlueskyRequestExecutor` is a `struct` (value type, implicitly Sendable when all properties are Sendable)
- `BlueskySessionService` is `@MainActor` with an in-memory `cachedSessions: [String: BlueskySession]` dictionary

## Error Handling

**Strategy:** Layered error normalization via `AppError`

**Error types:**
- `BlueskyAPIError` (`Sources/Domain/Services/BlueskyAPIError.swift`, lines 1-24): Network-level errors (invalidURL, invalidResponse, unauthorized, missingCredentials, server)
- `AppError` (`Sources/Shared/Support/AppError.swift`, lines 1-88): User-facing normalized error with `AppErrorCategory` (authentication, network, decoding, validation, server, cancellation, unknown)
- `KeychainError` (`Sources/Domain/Services/KeychainService.swift`, lines 4-6): Keychain-specific errors

**Error transformation chain:**
1. `BlueskyRequestExecutor` throws `BlueskyAPIError`
2. ViewModel catches error, calls `AppError.userMessage(from:)` which categorizes and produces user-readable string
3. ViewModel sets `@Published var errorMessage: String?` displayed via `.alert()` in view

**Pattern examples:**
- `AppError.userMessage(from:)` (line 72-74): Entry point for error normalization
- `AppError.from(_:)` (lines 21-70): Maps `BlueskyAPIError`, `DecodingError`, `URLError`, `CancellationError` to categorized `AppError`
- Views display errors via alerts: `.alert(loc("..."), isPresented: .constant(viewModel.errorMessage != nil))` (e.g., `ListDetailView.swift` line 69)

## Controller Layer Architecture

**Role:** Extract reusable business logic from ViewModels into testable classes

**Located at:** `Sources/Features/Lists/`

| Controller | File | Responsibility |
|---|---|---|
| `ListMembersController` | `ListMembersController.swift` | Manages member pagination cursor, `loadMembers()` / `loadMoreMembers()`, deduplication |
| `ListImportController` | `ListImportController.swift` | Parses raw text into handles/DIDs, resolves profiles, classifies items |
| `ListDiffController` | `ListDiffController.swift` | Compares two lists (overlap, onlyInCurrent, onlyInOther), exports CSV rows |
| `ListMergeController` | `ListMergeController.swift` | List merge logic (found but not analyzed in detail) |

All are `@MainActor final class`, created by `ListDetailViewModel` at init (lines 34-40 of `ListDetailViewModel.swift`).

## Cross-Cutting Concerns

**Logging:**
- `AppLogger` enum (`Sources/Shared/Support/AppLogger.swift`, lines 1-11): `os.Logger` with 4 categories: `search`, `persistence`, `moderation`, `performance`
- Used throughout services, stores, and view models for debug logging
- Performance logging measures elapsed time with `CFAbsoluteTimeGetCurrent()`

**Validation:**
- Ad-hoc validation in ViewModel methods (e.g., `ListDetailViewModel+Data.swift` lines 265-268: title must not be empty)
- `AppError(category: .validation, ...)` for structured validation errors (e.g., `ListImportController.swift` line 16)

**Authentication:**
- Handled via `BlueskySessionService`: create session, persist to Keychain, refresh JWT, recover from unauthorized
- `performAuthenticatedRequest()` (lines 91-108 of `BlueskySessionService.swift`) wraps operations with automatic token refresh on 401

**Persistence:**
- Accounts: `UserDefaults` (metadata) + `KeychainService` (passwords, session tokens)
- Workspace preferences: `UserDefaults` via `WorkspacePreferencesStore`
- Audit log/snapshots: `UserDefaults` as JSON via `ModerationAuditStore`
- Dashboard data: File-based JSON cache via `DashboardCache`
- Relationships: File-based JSON cache via `RelationshipCache`

---

*Architecture analysis: 2026-05-12*
