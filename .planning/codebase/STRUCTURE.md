# Codebase Structure

**Analysis Date:** 2026-05-12

## Directory Layout

```
BlueskyModeration/
├── Sources/
│   ├── App/                          # App entry, DI, root navigation, settings
│   ├── Features/
│   │   ├── Lists/                    # List management (main feature)
│   │   ├── Profile/                  # Profile inspector, network graph
│   │   └── Accounts/                 # Account management
│   ├── Domain/
│   │   ├── Models/                   # Data models
│   │   └── Services/                 # Network, stores, caches, persistence
│   │       └── Preview/              # Mock services for SwiftUI previews
│   └── Shared/
│       ├── Components/               # Reusable SwiftUI views
│       ├── Support/                  # Utilities (errors, logging, helpers)
│       ├── Theme/                    # Colors, styles, glass effects
│       └── Localizations/            # i18n engine + 16 language JSON files
├── Tests/
│   └── BlueskyModerationTests/       # Unit tests
├── UITests/
│   └── BlueskyModerationUITests/     # UI tests
├── WidgetExtension/
│   └── RulyxWidget.swift             # iOS widget
├── Assets/
│   └── Assets.xcassets/              # App icons, images
├── project.yml                       # XcodeGen project configuration
├── .swiftformat                      # SwiftFormat rules
├── .swiftlint.yml                    # SwiftLint rules
└── .swift-version                    # Swift version pinning
```

## Directory Purposes

### `Sources/App/` — Application Entry & Container

**Purpose:** App entry point, dependency injection container, root navigation, settings

**Key files:**
- `BlueskyModerationApp.swift` (37 lines): `@main` iOS entry point — creates `AppDependencies`, manages lock screen overlay with `ZStack` + transition, injects environment objects, restores sessions on `.task {}`
- `BlueskyModerationApp+macOS.swift` (26 lines): `#if os(macOS)` alternate `@main` entry — same DI pattern but separate target
- `AppDependencies.swift` (29 lines): `@MainActor final class ObservableObject` — creates all services in `init()`, exposes as properties (accountStore, listService, profileService, workspaceStore, actionPresetStore, blueskyClient, localizationManager). **Single source of truth for DI.**
- `RootView.swift` (115 lines): `TabView` with 4 tabs (moderation via `ListsView`, settings via `SettingsView`, info via `InfoView`, accounts via `AccountTabView`), onboarding sheet, preferred color scheme `.dark`
- `SettingsView.swift` (138 lines): Language picker, debug mode toggle, cache clearing, Face ID lock toggle
- `InfoView.swift`: App info/about screen
- `PrivacyInfo.xcprivacy`: Apple privacy manifest

### `Sources/Features/Lists/` — Core List Management Feature

**Purpose:** The primary feature — list CRUD, member management, search, import, comparison, bulk actions

**Files breakdown:**

**Views:**
- `ListsView.swift` (367 lines): Main list dashboard — profile card, relationship grid (followers/following/blocking/blocked-by), lists grouped by kind (moderation/regular), sheets for create list, account picker, bulk lookup. Uses `NavigationStack` + `.navigationDestination()`
- `ListDetailView.swift` (366 lines): Detail screen for a single list — member list, search, import, comparison, batch actions, edit metadata, export CSV. Multiple sheets for edit/import/preview/file picker
- `ListRowView.swift`: Row template for a list in ListsView
- `DashboardView.swift`: Alternate dashboard (less used)
- `BlueskyProfileView.swift`: Profile card display within list context
- `RelationshipsView.swift`: Followers/following/blocking/blocked-by browser
- `CreateListSheet.swift`: Sheet form for creating new list
- `ListTemplatesView.swift`: Template-based list creation
- `ActionPresetsView.swift`: Preset actions management
- `ModerationRulesView.swift`: Moderation rules configuration
- `ReportGeneratorView.swift`: Report generation screen
- `TrendDetectionView.swift`: Trend/membership change detection
- `PendingActionsSheet.swift`: Queued action review sheet

**ViewModels:**
- `ListsViewModel.swift` (115 lines): `@MainActor final class ObservableObject` — loads lists, profile, blocking counts for dashboard. Stale-while-revalidate pattern via `DashboardCache`
- `ListDetailViewModel.swift` (41 lines): Base VM with all `@Published` state vars and controller references. Controllers created inline: `membersController`, `importController`, `diffController`, `batchController`
- `ListDetailViewModel+Data.swift` (288 lines): Extension — member loading, pagination, import preview/commit, list comparison, export, metadata update
- `ListDetailViewModel+Bulk.swift` (488 lines): Extension — selection management (search/member/comparison), bulk add/remove/copy/move/block/mute/unblock, batch result handling
- `ListDetailViewModel+Search.swift`: Extension — actor search, pagination
- `BlueskyProfileViewModel.swift`: ViewModel for profile display in list context

**Controllers (reusable business logic):**
- `ListMembersController.swift` (62 lines): Pagination cursor management, member deduplication
- `ListImportController.swift` (156 lines): Parse raw text (handles/DIDs/URLs), resolve profiles, classify import items (ready/duplicate/alreadyPresent/unresolved)
- `ListDiffController.swift` (88 lines): Two-list comparison (overlap/onlyInCurrent/onlyInOther), CSV diff export
- `ListBatchController.swift` (76 lines): Sequential batch execution with progress callbacks, 3x retry per item, rate-limiting delay
- `ListMergeController.swift`: List merge logic

**Supporting files:**
- `ListDetailModels.swift` (186 lines): `ListBulkActionResult`, `ListComparisonReport`, `BatchProgress`, `ImportPreview`, `ImportPreviewItem`, `ComparisonBucket` and their nested types
- `ListDetailSheets.swift`: Sheet view builders for edit metadata, import preview
- `ListDetailView+Helpers.swift`: Helper views/extensions for the detail view
- `ListDetailMembersSection.swift`: Members section subview
- `ListDetailSnapshotSection.swift`: Snapshot/audit subview
- `ListDetailSearchSection.swift`: Search subview
- `ListDetailComparisonSection.swift`: Comparison subview

### `Sources/Features/Profile/` — Profile Inspection Feature

**Purpose:** Inspecting Bluesky profiles, list memberships, and social graph

**Files:**
- `ProfileInspectorView.swift` (372 lines): Search handles/DIDs, view profile details, list memberships, starter pack memberships, block/mute controls
- `ProfileInspectorViewModel.swift` (169 lines): `@MainActor ObservableObject` — search with debounce via `SearchToken` cancellation pattern, inspect profile, error handling
- `BulkProfileLookupView.swift`: Lookup multiple profiles at once
- `BulkProfileLookupViewModel.swift`: ViewModel for bulk lookup
- `NetworkGraphView.swift`: Social graph visualization
- `FollowerDiffView.swift`: Compare followers/following between two points

### `Sources/Features/Accounts/` — Account Management Feature

**Purpose:** Adding, switching, labeling, and removing Bluesky accounts

**Files:**
- `AccountTabView.swift` (135 lines): Account list with active state, swipe-to-delete, drag-to-reorder, edit label sheet, add account sheet
- `AddAccountView.swift`: Form for adding new account (handle + app password)
- `AccountRowView.swift`: Row template for account display

### `Sources/Domain/Models/` — Data Models

**Purpose:** Value types representing Bluesky entities and app state

**Files:**
- `AppAccount.swift` (38 lines): `Identifiable, Codable, Hashable` struct — id, handle, displayName, did, avatarURL, pdsURL, entrywayURL, label, timestamps
- `BlueskyList.swift` (46 lines): `Identifiable, Hashable, Codable` struct — id (AT URI), name, description, memberCount, kind (moderation/regular), avatarURL. Nested `Kind` enum with purposeIdentifier mapping
- `BlueskyListMember.swift` (13 lines): `Identifiable, Hashable` struct — recordURI + `BlueskyActor`
- `BlueskyActor.swift` (39 lines): `Identifiable, Hashable, Codable` struct — did, handle, displayName, avatarURL, createdAt. Computed `title`, `isNew` (account < 4 weeks old)
- `BlueskyProfile.swift` (43 lines): `Identifiable, Hashable, Codable` struct — full profile with viewer state, labels, counts. Nested `BlueskyViewerState` struct
- `ProfileMembershipModels.swift` (52 lines): `ProfileListMembership`, `ProfileStarterPackMembership`, `ProfileInspection` structs

**All models conform to `Identifiable` + `Hashable` + `Codable`. They use `id` property (not `@ID` macro). No Sendable conformance found.**

### `Sources/Domain/Services/` — Services, Stores, Caches

**Purpose:** Network communication, session management, data persistence, caching

**Network Services:**
- `BlueskyRequestExecutor.swift` (131 lines): `struct BlueskyRequestExecuting` protocol + `BlueskyRequestExecutor` struct — generic `send<>` method for AT Protocol XRPC calls. Handles JSON encode/decode, auth headers, User-Agent, URLSession with optional certificate pinning (`PinningDelegate` lines 115-131)
- `BlueskySessionService.swift` (363 lines): `@MainActor protocol BlueskySessionServicing` + `BlueskySessionService` — authentication, JWT refresh, session persistence in Keychain, `performAuthenticatedRequest()` with auto-reauth on 401. Also contains response DTOs (`CreateSessionRequest/Response`, `DIDDocument`, `DIDService`)
- `BlueskyListService.swift` (286 lines): `@MainActor final class BlueskyListService: ObservableObject, BlueskyListServicing` — list CRUD operations
- `BlueskyProfileService.swift` (408 lines): `@MainActor final class BlueskyProfileService: ObservableObject, BlueskyProfileInspecting` — profile/actor operations
- `LiveBlueskyClient.swift` (927 lines): `@MainActor class LiveBlueskyClient: ObservableObject, BlueskyAuthenticating, BlueskyListServicing, BlueskyProfileInspecting` — **largest file in codebase** — unified client that composes `BlueskyRequestExecutor` + `BlueskySessionService`, adds Clearsky integration (blocking, blocked-by), PLC audit log, profile batch resolution, followers/following with pagination
- `PreviewBlueskyClient.swift` (428 lines): Subclass of `LiveBlueskyClient` for SwiftUI previews — overrides all methods with fake data + simulated delays

**Protocols:**
- `BlueskyListServicing.swift` (14 lines): `@MainActor` protocol with list CRUD methods
- `BlueskyProfileInspecting.swift` (17 lines): `@MainActor` protocol with profile/actor methods
- `BlueskyRequestExecuting.swift` (inside `BlueskyRequestExecutor.swift`): `Sendable` protocol for HTTP
- `KeychainServicing` (inside `KeychainService.swift`): Keychain abstraction protocol

**Stores:**
- `AccountStore.swift` (244 lines): `@MainActor final class ObservableObject` — accounts list, active account, add/remove/switch/label/reorder, UserDefaults persistence, Keychain password management, iCloud account sync via `NotificationCenter`
- `ModerationWorkspaceStore.swift` (106 lines): `@MainActor final class ObservableObject` — orchestrates `WorkspacePreferencesStore` + `ModerationAuditStore` + `ActionQueueStore` via Combine `objectWillChange.sink()`
- `WorkspacePreferencesStore.swift` (144 lines): `@MainActor final class ObservableObject` — saved/recent profile searches, selected tab, last query — persisted to UserDefaults as JSON
- `ModerationAuditStore.swift` (244 lines): `@MainActor final class ObservableObject` — list membership snapshots (capture/diff/compare), operation log — persisted to UserDefaults as JSON
- `ActionQueueStore.swift` (112 lines): `@MainActor final class ObservableObject` — queued actions with sequential processing via `ListBatchController`, progress tracking, cancel/retry

**Support:**
- `KeychainService.swift` (74 lines): Swift Security framework wrapper with `save()`/`read()`/`delete()` for generic passwords
- `BlueskyAPIError.swift` (29 lines): `BlueskyAPIError` enum (invalidURL, invalidResponse, unauthorized, missingCredentials, server) + `APIErrorPayload` Decodable
- `DashboardCache.swift` (41 lines): File-based JSON cache for dashboard data (lists + profile + counts)
- `RelationshipCache.swift` (29 lines): File-based JSON cache for follower/following actor lists
- `iCloudAccountSync.swift`: iCloud account synchronization
- `ActionPresetStore.swift`: Preset actions store (referenced in AppDependencies)

### `Sources/Shared/Components/` — Reusable UI Components

**Purpose:** Shared SwiftUI views used across features

**Files:**
- `BlueskyActorRow.swift`: Actor handle/displayName/avatar row
- `AccountSummaryCard.swift`: Account summary card for profile header
- `AccountChip.swift`: Compact account chip
- `AccountSwitcherSheet.swift`: Full account switcher sheet
- `AccountQuickSwitcherSheet.swift`: Quick account switcher (iPad)
- `iPadAccountSwitcher.swift`: iPad-specific account switcher
- `ActorSearchResultRow.swift`: Search result row
- `SkeletonRow.swift` / `SkeletonCard.swift`: Loading skeleton views
- `StatePanels.swift`: Status/state display panels
- `OfflineBanner.swift`: Network offline banner
- `ActivityLogView.swift`: Moderation activity log
- `LockScreenView.swift`: Face ID/passcode lock screen

### `Sources/Shared/Support/` — Utilities and Cross-Cutting

**Purpose:** Shared utilities, error handling, logging, helpers

**Files:**
- `AppError.swift` (88 lines): Normalized error handling — `AppError` struct with `AppErrorCategory` enum, `from(_:)` factory mapper, `userMessage(from:)` helper, cancellation detection
- `AppLogger.swift` (11 lines): `os.Logger` wrapper with 4 categories: `search`, `persistence`, `moderation`, `performance`
- `LoadableState.swift` (36 lines): Generic loading state enum (idle/loading/loaded/failed) — defined but not widely used
- `AppLockManager.swift` (107 lines): Face ID/passcode lock manager with timeout configuration
- `NetworkMonitor.swift` (26 lines): NWPathMonitor wrapper for connectivity status
- `SearchToken.swift`: Cancellation token for debounced search
- `ModerationRuleStore.swift`: Moderation rules storage
- `iCloudAccountSync.swift`: iCloud sync integration
- `String+CSV.swift`: CSV serialization helper
- `URL+Bluesky.swift`: URL extension for Bluesky URLs

### `Sources/Shared/Theme/` — Visual Theming

**Purpose:** App branding colors, glass effects

**Files:**
- `Color+BlueskyModeration.swift` (15 lines): `.skyPrimary`, `.skyAccent` with light/dark mode adaptivity
- `GlassSupport.swift`: Glass/transparency effects (referenced as `.glassProminentButton()`)

### `Sources/Shared/Localizations/` — Internationalization

**Purpose:** Multi-language support engine and translation files

**Files:**
- `LocalizationManager.swift` (85 lines): `@MainActor final class ObservableObject` — loads JSON translation files from bundle, manages language selection, `localized()` and `localizedPlural()` methods, fallback to English keys
- `LocalizedText.swift` (16 lines): `LText` SwiftUI view + `localizedString()` view extension. Global `loc(_ key:)` function (line 83-85)
- 16 JSON language files: `en.json`, `de.json`, `fr.json`, `it.json`, `ja.json`, `zh.json`, `es.json`, `pt.json`, `ko.json`, `ru.json`, `ar.json`, `nl.json`, `pl.json`, `tr.json`, `th.json`, `vi.json`

## Naming Conventions

**Files:**
- PascalCase for Swift files matching the primary type: `BlueskyList.swift`, `AppDependencies.swift`, `ListDetailView.swift`
- Domain models: `Bluesky[Entity].swift` pattern (BlueskyActor, BlueskyList, BlueskyProfile, BlueskyListMember)
- Feature files: `[Feature]View.swift`, `[Feature]ViewModel.swift`, `[Feature]Controller.swift`
- ViewModel extensions: `[Feature]ViewModel+[Concern].swift` (e.g., `ListDetailViewModel+Data.swift`, `ListDetailViewModel+Bulk.swift`)
- Protocols: `[Entity]Servicing` / `[Entity]Inspecting` / `[Entity]Executing` (gerund form, e.g., `BlueskyListServicing`, `BlueskyProfileInspecting`, `BlueskyRequestExecuting`)
- Services: `Bluesky[Function]Service.swift` (e.g., `BlueskyListService`, `BlueskyProfileService`)
- Stores: `[Domain]Store.swift` (e.g., `AccountStore`, `ActionQueueStore`, `ModerationAuditStore`)
- Test files: `[TargetName]Tests.swift` for test classes, matching production file names

**Types:**
- Classes: `@MainActor final class` for ViewModels, stores, services, controllers
- Structs: All models (`BlueskyList`, `AppAccount`, etc.)
- Enums: `AppErrorCategory`, `WorkspaceTab`, `ComparisonBucket`, `QueuedActionStatus`
- Protocols: PascalCase, usually `[Adjective][Noun]Servicing` or `[Noun][Verb]ing`

**Functions/Methods:**
- Swift naming conventions: `loadMembers()`, `fetchLists()`, `addAccount()`, `performAuthenticatedRequest()`
- `async` functions use `throws` for error propagation
- Completion handlers use closure parameters (e.g., `onProgress: ((BatchProgress) -> Void)?`)

**Variables:**
- camelCase: `isLoading`, `activeAccount`, `errorMessage`, `membersController`

## How Features Are Organized

**By domain/feature (top-level grouping), by layer within each feature:**

```
Sources/Features/{Feature}/
├── *View.swift              # SwiftUI view structs
├── *ViewModel.swift         # ObservableObject classes 
├── *ViewModel+*.swift       # Extensions for logical grouping
├── *Controller.swift        # Business logic controllers
├── *Models.swift            # Feature-specific value types
├── *Sheets.swift            # Sheet views
└── *Section.swift           # Section sub-views
```

This is a **feature-first** organization with layer-based naming within each feature folder.

## Where to Add New Code

**New Feature:**
1. Create `Sources/Features/{FeatureName}/` directory
2. Add `{FeatureName}View.swift` (SwiftUI View)
3. Add `{FeatureName}ViewModel.swift` (`@MainActor final class: ObservableObject`)
4. Add controllers as `{FeatureName}Controller.swift` if business logic is complex
5. Add feature-specific types in `{FeatureName}Models.swift`
6. Add tests in `Tests/BlueskyModerationTests/{FeatureName}Tests.swift`

**New Service:**
1. Define protocol in `Sources/Domain/Services/{Name}Servicing.swift` (or extend existing)
2. Implement in `Sources/Domain/Services/{Name}Service.swift` with `@MainActor final class`
3. Register in `AppDependencies.swift` (add property + init construction)
4. Inject via `.environmentObject()` in app entry point

**New Store:**
1. Create in `Sources/Domain/Services/{Name}Store.swift` as `@MainActor final class: ObservableObject`
2. Use `UserDefaults` for lightweight persistence or file-based JSON for larger data
3. Wire into `ModerationWorkspaceStore` if it relates to workspace state (with Combine bindings)
4. Register in `AppDependencies.swift` if needed by views, or inject through workspace store

**New Model:**
1. Add to `Sources/Domain/Models/{Name}.swift`
2. Conform to `Identifiable`, `Hashable`, `Codable`, `Sendable` where appropriate
3. Use `let` for identity properties, `var` for mutable properties

**New Shared Component:**
1. Add to `Sources/Shared/Components/{Name}.swift`
2. Accept dependencies via `@EnvironmentObject` or direct parameters
3. Preview: provide `.environmentObject(MockService())`

**New Localization Key:**
1. Add key to all 16 JSON files in `Sources/Shared/Localizations/`
2. Use `loc("key.path")` in views or `LocalizationManager.shared.localized("key.path")` in code
3. Follow dot-notation: `screen.component.description`

## Special Directories

**`Tests/BlueskyModerationTests/`:** Unit tests matching production structure — 26 test files covering ViewModels, Services, Controllers, and utilities. Uses `import XCTest @testable import BlueskyModeration`.

**`UITests/BlueskyModerationUITests/`:** UI test targets (minimal content).

**`WidgetExtension/`:** Single-file widget (`RulyxWidget.swift`) for iOS home screen.

**`Assets/Assets.xcassets/`:** App icon, logo image, Contents.json metadata. No other asset catalogs.

**`DerivedData/`:** Build artifacts (gitignored in production, present for development). **Not committed.**

**.planning/:** Project management artifacts (roadmap, phase plans, etc.) — development meta-data.

---

*Structure analysis: 2026-05-12*
