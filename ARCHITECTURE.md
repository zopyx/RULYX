# Rulyx (BlueskyModeration) — Architecture Document

## 1. Project Overview

Rulyx is a native iOS-only SwiftUI application for Bluesky moderation. It enables multi-account management, moderation list CRUD, profile inspection, follower/following management, timeline browsing, and batch automation — all through the AT Protocol (ATP).

| Attribute | Detail |
|-----------|--------|
| Platform | iPhone only, iOS 17+ |
| Language | Swift 6 (strict concurrency) |
| UI Framework | SwiftUI |
| Architecture | MVVM + Service Layer + ObservableObject Stores |
| DI Pattern | Manual via `AppDependencies` (EnvironmentObject injection) |
| Build Tool | xcodegen (project.yml → .xcodeproj) |
| Bundle ID | `com.ajung.BlueskyModeration` |
| Display Name | RULYX |
| Target | iPhone only (`TARGETED_DEVICE_FAMILY = "1"`) |

## 2. Directory Structure

```
BlueskyModeration/
├── Sources/
│   ├── App/                  # App entry, DI, root navigation
│   ├── Domain/
│   │   ├── Models/           # Domain models (Codable, Sendable)
│   │   └── Services/         # Network services, stores, caches
│   ├── Features/
│   │   ├── Accounts/         # Account management UI
│   │   ├── Chat/             # Direct messaging (beta)
│   │   ├── Lists/            # Moderation lists (core feature area)
│   │   │   └── Profile/      # User posts, media, thread views
│   │   ├── Profile/          # Profile inspector, bulk lookup, follower diff
│   │   └── Timeline/         # Timeline feed viewer (beta)
│   └── Shared/
│       ├── Components/       # Reusable UI components
│       ├── Localizations/    # i18n (16 languages, JSON)
│       ├── Support/          # Utilities (error handling, logging, etc.)
│       └── Theme/            # Colors, gradients, glass effects
├── Tests/                    # Unit tests (28 files)
├── UITests/                  # UI tests (1 file)
├── Assets/                   # Asset catalog
├── WidgetExtension/          # iOS widgets
└── project.yml               # XcodeGen project definition
```

## 3. Architectural Pattern: MVVM + Store + Service

The app follows a layered MVVM architecture with three distinct tiers:

```
┌──────────────────────────────────────────────────────────────┐
│                        View Layer                            │
│  SwiftUI Views (@EnvironmentObject for DI)                   │
├──────────────────────────────────────────────────────────────┤
│                     ViewModel Layer                          │
│  @MainActor final class: ObservableObject                    │
│  Owns UI state, coordinates service calls                   │
├──────────────────────────────────────────────────────────────┤
│                      Store Layer                             │
│  @MainActor final class: ObservableObject                    │
│  Owns persistent/derived state, caches, business logic       │
├──────────────────────────────────────────────────────────────┤
│                    Service Layer                             │
│  Protocols + implementations                                 │
│  Stateless, network-aware, session-aware                     │
├──────────────────────────────────────────────────────────────┤
│                   Network Layer                              │
│  BlueskyRequestExecutor → URLSession                         │
│  Certificate pinning, JWT auth, AT Protocol XRPC calls       │
└──────────────────────────────────────────────────────────────┘
```

### Data Flow

1. **View** triggers action (button tap, .task, .onChange)
2. **ViewModel** receives action, updates loading state (`@Published`)
3. **ViewModel** calls **Store** method or **Service** method
4. **Service** performs authenticated XRPC request via `BlueskyRequestExecutor`
5. Response flows back: Service → ViewModel → View (via `@Published` properties)
6. Side effects (persistence, analytics) happen in **Stores**

## 4. Dependency Injection

All dependencies are created in `AppDependencies` and injected as `@EnvironmentObject` at the root level.

```
BlueskyModerationApp
  └── AppDependencies (StateObject)
       ├── accountStore: AccountStore
       ├── listService: BlueskyListService
       ├── profileService: BlueskyProfileService
       ├── workspaceStore: ModerationWorkspaceStore
       ├── actionPresetStore: ActionPresetStore
       ├── blueskyClient: LiveBlueskyClient
       ├── localizationManager: LocalizationManager (singleton)
       ├── mutedWordsStore: MutedWordsStore
       ├── analyticsStore: AnalyticsStore
       ├── chatStore: ChatStore
       └── pushNotificationCoordinator: PushNotificationCoordinator
```

The `AppDependencies` init has two paths:
- **Normal**: Real `BlueskyRequestExecutor`, `KeychainService`, `LiveBlueskyClient`
- **UI Testing** (`--uitesting` flag): `AccountStore(preview: true)`, `PreviewBlueskyClient`

Views receive dependencies via:
```swift
@EnvironmentObject private var accountStore: AccountStore
@EnvironmentObject private var blueskyClient: LiveBlueskyClient
```

The active account-scoped dependencies (app password) are looked up on-demand via `accountStore.appPassword(for:)`.

## 5. Navigation & Routing

### Tab Navigation (RootView)

Five-tab `TabView` with `NavigationStack`-based sub-navigation:

| Tab | Tag | Visibility | Icon |
|-----|-----|-----------|------|
| Moderation | `.moderation` | Always | `checklist.checked` |
| Info | `.info` | Always | `sparkles.rectangle.stack` |
| Timeline | `.timeline` | Beta flag | `clock.arrow.circlepath` |
| Chat | `.chat` | Beta flag | `bubble.left.and.bubble.right` |
| Settings | `.settings` | Always | `gearshape` |
| Accounts | `.account` | Always | `person.circle` |

### Tab Selection Management

`ModerationWorkspaceStore.selectedTab` is the source of truth. Changes persist to `WorkspacePreferencesStore` (backed by `UserDefaults`). Tab selection is restored across app launches.

Moderation tab features `NavigationSplitView` with adaptive layout:
- **Compact** (iPhone): Single-column `NavigationStack` via `ListsView`
- **Regular** (iPad/landscape): Three-column `NavigationSplitView` sidebar → content → detail

A `moderationNavigationResetToken` (UUID) allows programmatic reset of all moderation navigation state.

### Deep Navigation Patterns

**Programmatic navigation** via state-driven presentation:
```swift
@State private var showProfile = false
// ...
.sheet(isPresented: $showProfile) { ProfileInspectorView() }
```

**NavigationStack** with `.navigationDestination` for drill-down:
```swift
NavigationStack {
    List {
        ForEach(lists) { list in
            NavigationLink(list.name, value: list)
        }
    }
    .navigationDestination(for: BlueskyList.self) { list in
        ListDetailView(list: list)
    }
}
```

## 6. Model Layer

Domain models in `Sources/Domain/Models/` are:
- **Value types** (`struct`)
- **Codable** (JSON serialization for API, persistence, previews)
- **Hashable** (SwiftUI diffing, sets, dictionary keys)
- **Identifiable** (SwiftUI lists)

Key models:

| Model | Key Properties | Role |
|-------|---------------|------|
| `AppAccount` | id, handle, did, pdsURL, entrywayURL, label | Represents a login identity |
| `BlueskyList` | id (AT URI), name, kind (.moderation/.regular), memberCount | Moderation/curation list |
| `BlueskyListMember` | recordURI, actor (BlueskyActor) | Actor in a list |
| `BlueskyActor` | did, handle, displayName, avatarURL, createdAt | Abstract person reference |
| `BlueskyProfile` | did, handle, displayName, labels, viewerState, stats | Full resolved profile |
| `BlueskySession` | did, handle, accessJWT, refreshJWT, pdsURL | Auth session (Keychain-backed) |
| `BlueskyViewerState` | muted, blockedBy, isBlocking, isFollowing, etc. | Viewer-relative state |
| `ChatConversation` | id, lastMessageAt, members | Chat conversation model |
| `ChatMessageKind` | text, sender, timestamp | Chat message model |

The app also uses DTO models (`BlueskyAPIDTOs.swift`, `ChatAPIDTOs.swift`) that mirror the AT Protocol XRPC response shapes — separate from domain models to decouple API shape from app logic.

## 7. Service Layer

Services live in `Sources/Domain/Services/` and are organized by protocol:

### Protocol Hierarchy

```
BlueskyRequestExecuting (Sendable)
    └── BlueskyRequestExecutor
    
BlueskySessionServicing (@MainActor)
    └── BlueskySessionService
    
BlueskyListServicing (@MainActor)
    ├── BlueskyListService
    └── (also) LiveBlueskyClient
    
BlueskyProfileInspecting (@MainActor)
    └── (via) LiveBlueskyClient
    
ChatServicing (@MainActor)
    └── ChatService
    
KeychainServicing
    └── KeychainService
```

### BlueskyRequestExecutor

The lowest-level network abstraction. Sends XRPC calls via URLSession:
- Constructs URLs: `{hostURL}/xrpc/{path}`
- Manages Authorization header (Bearer JWT)
- Accepts optional body (Encodable) and query items
- Decodes typed responses
- Handles 401 → throws `.unauthorized`
- Handles error payloads from API
- Logs request duration via `AppLogger.performance`
- Supports certificate pinning (`PinningDelegate`) for `bsky.social`
- Empty response handling (decodes `{}` for void endpoints)

### BlueskySessionService

Manages the authentication lifecycle:
- `authenticate(handle:appPassword:entrywayURL:)` — AT Protocol `com.atproto.server.createSession`
- `persistSession/deletePersistedSession/restoreSessions` — Keychain-backed
- `performAuthenticatedRequest` — Core auth wrapper:
  1. Retrieves/restores session from cache or Keychain
  2. Checks JWT expiry (auto-refresh within 60s of expiry)
  3. On 401 from operation, attempts refresh → re-authenticates as fallback
- DID resolution chain: handle → PLC directory → PDS URL
- Supports custom entryway URLs (any PDS, not just bsky.social)

### BlueskyProfileInspecting Protocol

Protocol defining profile inspection operations. `LiveBlueskyClient` conforms to both `BlueskyListServicing` and `BlueskyProfileInspecting`.

### LiveBlueskyClient

The largest service class (~1000 lines). A facade that implements:
- `BlueskyAuthenticating` — auth delegation to `BlueskySessionService`
- `BlueskyListServicing` — list CRUD
- `BlueskyProfileInspecting` — profile inspection
- Timeline operations (timeline, custom feeds, author feed)
- Post operations (create/delete, like, repost, reply)
- Block/mute/follow operations
- Clearsky integration (blocklist, blocked-by, lists)
- PLC audit log retrieval
- Media upload (blob)
- Batch profile resolution (25 per batch, concurrent tasks)

Each operation wraps the `sessionService.performAuthenticatedRequest` closure pattern.

### PreviewBlueskyClient

Subclass of `LiveBlueskyClient` overriding all methods with mock data:
- Simulated latency (80-200ms `Task.sleep`)
- Deterministic data based on account handle hash
- Supports paginated mock data (page size 3)
- Used in SwiftUI previews and UI tests

### KeychainService

Wrapper around iOS Security framework (`SecItemAdd`/`SecItemCopyMatching`/`SecItemDelete`):
- Storage: `kSecClassGenericPassword`
- Accessibility: `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`
- Two namespaces: passwords service + session service

## 8. Store Layer

Stores are `@MainActor` `ObservableObject` classes that own persistent state. They are the "source of truth" for the application.

| Store | Persistence | Key Responsibility |
|-------|-------------|-------------------|
| `AccountStore` | UserDefaults + Keychain | Account CRUD, active account, labels, iCloud sync |
| `ModerationWorkspaceStore` | UserDefaults (via sub-stores) | Tab selection, saved/recent searches, operation log, queued actions |
| `WorkspacePreferencesStore` | UserDefaults | Searches, tab state |
| `ModerationAuditStore` | UserDefaults | Operation log, list snapshots, snapshot comparison |
| `ActionQueueStore` | In-memory | Serial batch execution with progress tracking |
| `MutedWordsStore` | UserDefaults | Muted word list, filter predicate |
| `AnalyticsStore` | UserDefaults | Per-post engagement snapshots |
| `FeedStore` | UserDefaults | Custom feed URI, recent feeds (per-account) |
| `ChatStore` | In-memory | Conversations, messages, polling |
| `ActionPresetStore` | In-memory (via Codable) | Action presets |
| `ModerationRuleStore` | In-memory | If-then moderation rules |

### Store Interaction Pattern

The `ModerationWorkspaceStore` is a composite facade over `WorkspacePreferencesStore` and `ModerationAuditStore`. It uses Combine publishers to sync state:

```swift
preferencesStore.objectWillChange.sink { [weak self] in
    self?.syncFromPreferences()
}.store(in: &cancellables)
```

### AccountStore Details

- **Persistence**: Account metadata in UserDefaults (JSON-encoded `[AppAccount]`), passwords in Keychain
- **iCloud Sync**: Via `NSUbiquitousKeyValueStore` — pushes/pulls account metadata across devices
- **Notifications**: Observes `.iCloudAccountsReceived` for cross-device sync
- **Profile Refresh**: Periodically fetches account display names and avatars via `BlueskyProfileInspecting`

### Dashboard & Relationship Caches

File-system caches in the app's caches directory (`com.ajung.BlueskyModeration/`):
- `DashboardCache`: Cached lists, profile, block counts (one file per account DID)
- `RelationshipCache`: Cached follower/following lists

These are simple Codable read/write stores with manual invalidation on account switch.

## 9. ViewModel Layer

ViewModels follow a consistent pattern: `@MainActor final class: ObservableObject` with `@Published` properties for view state.

### Common ViewModel Patterns

**Loading State Management:**
SwiftUI views observe isLoading/isRefreshing/errorMessage directly.

**Search Token Pattern** (ProfileInspectorViewModel):
```swift
private var searchToken: SearchToken?
// ...
let token = SearchToken()
searchToken = token
// ... async search ...
guard searchToken?.matches(token) == true else { return }
```
This discards stale search results when the query changes before a previous search completes.

**Pagination:**
ViewModels track cursor, hasMore, and isLoadingMore to support cursor-based paginated loading.

### Key ViewModels

| ViewModel | Key Published State | Key Methods |
|-----------|-------------------|-------------|
| `ListsViewModel` | listsByKind, activeProfile, blocking/blockedBy counts, isLoading | load(), reset(), addList(), updateList() |
| `ListDetailViewModel` | members, filteredMembers, searchResults, bulkActionResult | Delegates to controllers |
| `ListBatchController` | Progress tracking | performBatch() with concurrency=5, retry=3 |
| `ListMembersController` | members pagination | loadMembers(), loadMoreMembers(), add/remove |
| `ListDiffController` | Comparison report | compareWithList() |
| `ListImportController` | Import preview | previewImport(), executeImport() |
| `FeedTimelineViewModel` | entries, state (TimelineState), newPostCount | loadTimeline(), refresh(), loadMore(), polling |
| `ProfileInspectorViewModel` | inspection, searchResults, isLoading | inspect(), search() |
| `BulkProfileLookupViewModel` | results, progress | lookup(), export() |
| `MediaBrowserViewModel` | posts, isLoading | loadPosts() |
| `UserPostsViewModel` | posts, timelineState | loadPosts(), loadMore() |
| `NetworkGraphView` | (no ViewModel — inline state) | Follower overlap visualization |

### TimelineState Enum

Timeline state is managed by a dedicated enum (not boolean flags):

```swift
enum TimelineState: Equatable {
    case initialLoading
    case loaded
    case refreshing
    case loadingMore
    case loadMoreFailed(String)
    case empty
    case failed(String)
    case exhausted
}
```

This enables proper state transitions and guards (e.g., prevents refresh during loadingMore).

### Controllers (Helper Objects)

The ListDetail feature decomposes complexity into focused controller objects:

- `ListMembersController` — Member CRUD with pagination
- `ListBatchController` — Concurrent batch operations (5 concurrent, 3 retries)
- `ListDiffController` — List-to-list difference computation
- `ListImportController` — Handle import preview and execution

These are plain objects owned by the ViewModel.

## 10. View Layer

### SwiftUI Conventions

- All views use `@EnvironmentObject` for injected dependencies
- Views avoid business logic — defer to ViewModels
- User-facing strings use `loc("key")` (never hardcoded English)
- Reusable components live in `Shared/Components/`
- Feature-specific views live in their feature directory

### Key Shared Components

| Component | Purpose |
|-----------|---------|
| `AccountChip` | Inline account avatar + name pill |
| `AccountSwitcherSheet` | Account switching modal |
| `AccountSummaryCard` | Dashboard account display card |
| `BlueskyActorRow` | Actor search result row |
| `SkeletonRow` | Loading placeholder row |
| `StatePanels` | Error/empty/idle state views |
| `OfflineBanner` | Network connectivity banner |
| `LockScreenView` | Biometric lock overlay |
| `SplashScreenView` | Animated splash |
| `InlineAnimatedMediaView` | GIF/video playback |
| `ImageCarouselView` | Photo browser |
| `LikesListView` | Post likes sheet |

### Adaptive Layout

The `ModerationSplitView` checks `horizontalSizeClass`:
- `.compact` → Simple `ListsView` with `NavigationStack`
- `.regular` → `NavigationSplitView` (3-column on iPad)

## 11. Network Layer

### AT Protocol XRPC

All communication uses the AT Protocol's XRPC mechanism:
- Base URL pattern: `{PDS_URL}/xrpc/{namespace}.{method}`
- Auth: Bearer JWT in Authorization header
- Pagination: cursor-based via `cursor` query parameter
- Method conventions: GET for reads, POST for writes

### Endpoint Categories

**Authentication:**
- `com.atproto.server.createSession` — Login
- `com.atproto.server.refreshSession` — Token refresh

**Identity:**
- `com.atproto.identity.resolveHandle` — Handle → DID
- `com.atproto.identity.resolveDid` — DID → PDS URL

**Lists:**
- `app.bsky.graph.getLists` — List enumeration
- `app.bsky.graph.getList` — List members (paginated)
- `app.bsky.graph.getListsWithMembership` — Lists with membership status
- `app.bsky.graph.getStarterPacksWithMembership` — Starter packs with membership

**Repository:**
- `com.atproto.repo.createRecord` — Create list item, list, block, follow, post, etc.
- `com.atproto.repo.deleteRecord` — Remove records
- `com.atproto.repo.putRecord` — Update list metadata
- `com.atproto.repo.uploadBlob` — Image/video upload

**Profiles:**
- `app.bsky.actor.getProfile` — Full profile
- `app.bsky.actor.getProfiles` — Batch profile (public API)
- `app.bsky.actor.searchActorsTypeahead` — Actor search

**Social:**
- `app.bsky.graph.getFollowers` — Paginated followers
- `app.bsky.graph.getFollows` — Paginated following
- `app.bsky.graph.muteActor` / `unmuteActor`

**Feed:**
- `app.bsky.feed.getTimeline` — Following timeline
- `app.bsky.feed.getFeed` — Custom feed
- `app.bsky.feed.getAuthorFeed` — User posts
- `app.bsky.feed.getPostThread` — Thread view
- `app.bsky.feed.getLikes` — Post likes

### Clearsky Integration

Third-party API for blocklist data:
- `public.api.clearsky.services/api/v1/anon/blocklist/{did}` — Blocked actors
- `public.api.clearsky.services/api/v1/anon/single-blocklist/{did}` — Blocked-by actors
- `api.clearsky.app/csky/api/v1/get-list/{handle}` — Clearsky list membership
- `public.api.clearsky.services/api/v1/anon/get-did/{handle}` — Handle → DID
- Public API `https://public.api.bsky.app` for batch profile resolution (no auth needed)

### Certificate Pinning

The `PinningDelegate` enforces SSL pinning for `bsky.social`:
- Validates leaf certificate SPKI (Subject Public Key Info) against a known hash
- Uses SHA-256 hashing
- Falls through to default handling for non-bsky.social hosts (custom PDS)
- Uses ephemeral session with pinning delegate

## 12. Persistence Strategy

| Data | Mechanism | Location |
|------|-----------|----------|
| Account metadata | UserDefaults (Codable JSON) | Standard |
| App passwords | Keychain | `com.ajung.BlueskyModeration.password` |
| Auth sessions | Keychain | `com.ajung.BlueskyModeration.session` |
| Workspace preferences | UserDefaults | Standard |
| Audit log | UserDefaults (Codable JSON) | Standard |
| List snapshots | UserDefaults (Codable JSON) | Standard |
| Analytics snapshots | UserDefaults (Codable JSON) | Standard |
| Muted words | UserDefaults (String array) | Standard |
| Feed preferences | UserDefaults (per-account, keyed by DID) | Standard |
| Dashboard cache | File system (JSON) | Caches directory |
| Follower/following cache | File system (JSON) | Caches directory |
| iCloud account sync | NSUbiquitousKeyValueStore | iCloud |

### Cache Invalidation

On account switch:
- `LiveBlueskyClient.clearCache()` — Clears URL cache + session cache
- `DashboardCache.clearAll()` — Removes all dashboard cache files
- `RelationshipCache.clearAll()` — Removes all relationship cache files

## 13. Security Architecture

### Credential Storage

- App passwords stored in Keychain (never UserDefaults)
- Auth sessions (JWT tokens) stored in Keychain
- Both use `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` — not backed up, not accessible when locked
- Session cache retained in memory for performance during active use

### Biometric Lock

- `AppLockManager` owns biometric state
- Face ID / Touch ID authentication via `LAContext`
- Auto-lock on `didEnterBackground` with configurable timeout
- Lock screen overlay prevents view access when locked

### SSL/TLS

- Certificate pinning for `bsky.social` via SPKI hash comparison
- Custom PDS endpoints use standard TLS validation (no pinning)

### JWT Handling

- Access JWT expiry decoded from base64 payload
- Auto-refresh triggered within 60 seconds of expiry
- Refresh uses dedicated `refreshSession` endpoint
- Fallback to full re-authentication if refresh fails

## 14. Internationalization

### Architecture

`LocalizationManager` is a singleton `ObservableObject`:
- Loads all 16 language JSON files on init
- Switches current language at runtime (no app restart needed)
- Falls back: current language → English → key string
- `loc("key")` global function for convenient access

### File Format

JSON key-value dictionaries per language:
```
Sources/Shared/Localizations/
├── en.json
├── de.json
├── fr.json
├── ... (16 languages total)
├── LocalizationManager.swift
└── LocalizedText.swift
```

### Pluralization

Custom `localizedPlural(_:count:)` method:
- Keys follow convention: `key_one` / `key_other`
- Supports English-style plural rules for all 16 languages
- `{count}` placeholder replaced at runtime

### Supported Languages

English, German, French, Italian, Japanese, Chinese, Spanish, Portuguese, Korean, Russian, Arabic, Dutch, Polish, Turkish, Thai, Vietnamese.

## 15. Account System

### Multi-Account Model

- Multiple `AppAccount` instances stored in UserDefaults
- Active account tracked by `activeAccountID`
- Each account has its own PDS URL (any AT Protocol provider)
- Account switching clears caches and re-fetches data

### Authentication Flow

```
1. User enters handle + app password (+ optional entryway URL)
2. BlueskySessionService.authenticate() 
   → resolve PDS URL from handle/DID
   → createSession via PDS
   → store session in memory + Keychain
   → store password in Keychain
3. AccountStore persists account metadata
4. iCloud sync pushes account metadata
```

### Session Recovery Flow

```
performAuthenticatedRequest(account, appPassword, operation):
  1. Check in-memory cache for session
  2. If not cached, restore from Keychain
  3. If restored + JWT near expiry → refresh
  4. Execute operation with access JWT
  5. If 401 → try refreshSession
  6. If refresh fails → full re-authenticate (requires appPassword)
  7. Retry operation with new session
```

### iCloud Sync

`iCloudAccountSync` uses `NSUbiquitousKeyValueStore` to sync account metadata across devices:
- Pushes on account add/remove/label/move
- Pulls on external change notification
- Merges new accounts that don't exist locally
- Syncs labels between devices
- Only syncs non-sensitive metadata (no passwords or tokens)

## 16. Timeline Feature Architecture

Timeline is behind a "show beta features" toggle.

### State Machine

```
initialLoading → loaded/empty/failed
loaded → refreshing/loadingMore/exhausted
refreshing → loaded/empty/failed (returns to previous on failure)
loadingMore → loaded/exhausted/loadMoreFailed
loadMoreFailed → loaded (user can retry)
```

### Polling

- 15-second polling interval
- Checks for new posts by comparing known URIs with fresh fetch (limit=5)
- `newPostCount` displays badge on tab
- Polling stops on account change

### Feed Selection

- `FeedStore` manages custom feed URI per account
- Falls back to following timeline (app.bsky.feed.getTimeline)
- Recent feeds tracked (max 5, by account DID)
- Feed picker in `FeedPickerView`

### Architecture

```
FeedTimelineViewModel
  ├── FeedStore (feed preferences)
  ├── MutedWordsStore (post filtering)
  ├── AnalyticsStore (engagement tracking)
  └── LiveBlueskyClient (API calls)
```

## 17. Moderation & List Management

### List Types

- `.moderation` → `app.bsky.graph.defs#modlist` (shield icon)
- `.regular` → `app.bsky.graph.defs#curatelist` (people icon)

### List Operations

| Operation | Endpoint |
|-----------|----------|
| Fetch lists | `app.bsky.graph.getLists` |
| Fetch members | `app.bsky.graph.getList` (paginated, all pages) |
| Add member | `com.atproto.repo.createRecord` (listitem) |
| Remove member | `com.atproto.repo.deleteRecord` (listitem) |
| Create list | `com.atproto.repo.createRecord` (list) |
| Update list | `com.atproto.repo.putRecord` (list) |
| Delete list | `com.atproto.repo.deleteRecord` (list) |

### Bulk Operations

`ListBatchController` executes bulk actions:
- 5 concurrent operations
- 3 retries per operation
- Progress reporting (completed/total, current handle)
- Error tolerance (continues on individual failures)
- Result summary (succeeded count, failure list)

### Action Queue

`ActionQueueStore` provides serial execution with:
- Queue: pending → running → completed
- Progress tracking per action (x of y complete)
- Cancellation support
- Retry support
- Used via `ModerationWorkspaceStore.queuedActions`

### Templates

6 pre-built list templates (not explored in detail, referenced in `ActionPresetStore`).

### Snapshots & Diff

`ModerationAuditStore` supports:
- Point-in-time snapshots of list membership (max 12 per list)
- Snapshot comparison (added/removed member diff)
- Change detection (skips identical snapshots)
- Operation log (last 25 operations)

## 18. Automation & Rules

### Action Presets

Pre-configured moderation action combinations (e.g., "block + report + add to list"), stored in `ActionPresetStore`.

### Moderation Rules

`ModerationRuleStore` supports if-then rules for automated actions.

### Report Generator

`ReportGeneratorView` for structured moderation reports.

## 19. Error Handling

### Normalized Error Model

All errors are normalized to `AppError`:

```swift
struct AppError: LocalizedError, Equatable {
    let category: AppErrorCategory  // .authentication, .network, .decoding, .validation, .server, .cancellation, .unknown
    let message: String
}
```

Conversion via `AppError.from(error:)` handles:
- `BlueskyAPIError` (6 cases)
- `DecodingError`
- `URLError` (network-specific messages)
- `CancellationError`
- Generic `Error` fallback

### View-Level Error Display

Pattern followed across views:
```swift
if let error = viewModel.errorMessage {
    ContentUnavailableView("Error", systemImage: "exclamationmark.triangle", description: Text(error))
}
```

### Partial Failure Tolerance

- ListsView: Shows cached data if refresh fails (tolerates stale data)
- Bulk operations: Continues on individual failures, reports at end
- Timeline: Returns to previous state on refresh failure

## 20. Logging

`AppLogger` wraps `os.Logger` with four categories:

| Logger | Category | Usage |
|--------|----------|-------|
| `AppLogger.search` | `search` | Profile search operations |
| `AppLogger.persistence` | `persistence` | Cache read/write, data persistence |
| `AppLogger.moderation` | `moderation` | Moderation operations, batch results |
| `AppLogger.performance` | `performance` | API request timing |

All logs use `os.Logger` privacy annotations (`.public` for non-sensitive data).

## 21. Testing Strategy

### Unit Tests (28 files)

Test coverage spans:
- **Stores**: AccountStore, ActionQueueStore, ModerationAuditStore, ModerationWorkspaceStore, WorkspacePreferencesStore
- **Services**: BlueskyListService, BlueskyProfileService, BlueskyRequestExecutor, KeychainService, MediaDownloadService, RelationshipCache
- **ViewModels**: ListDetail, Lists, ProfileInspector, MediaBrowser
- **Controllers**: ListBatchController, ListDiffController, ListImportController, ListMembersController
- **Models/Utilities**: AppError, BlueskyAPIDTOs, LoadableState, StringCSV, URLBluesky
- **Integration**: LiveAuthenticationTests, LiveBlueskyClientTests

### UI Tests (1 file)

Basic UI test target for snapshot-level verification.

### Preview System

`PreviewBlueskyClient` provides deterministic mock data for SwiftUI previews and UI tests. Mock services (`MockBlueskyListService`, `MockBlueskyProfileService`) in `Preview/` directory support unit testing.

## 22. Push Notifications

Architecture for push notification handling:

```
BlueskyAppDelegate
  ├── didRegisterForRemoteNotificationsWithDeviceToken → .pushTokenDidUpdate
  ├── didReceiveRemoteNotification → .pushNotificationDidReceive
  └── userNotificationCenter:willPresent → .pushNotificationDidReceive
      userNotificationCenter:didReceive → .pushNotificationDidOpen

PushNotificationCoordinator
  ├── BlueskyPushNotificationService (API calls)
  ├── syncAccounts() — Registers all accounts for push
  └── start() — Initial setup
```

## 23. Dependency Graph

A high-level dependency graph showing the direction of dependencies:

```
BlueskyModerationApp
  └── AppDependencies
       ├── AccountStore ────────────── KeychainService
       ├── ModerationWorkspaceStore ── WorkspacePreferencesStore
       │                            ── ModerationAuditStore
       │                            ── ActionQueueStore
       ├── LiveBlueskyClient ───────── BlueskySessionService
       │                         ──── BlueskyRequestExecutor
       ├── ChatStore ──────────────── ChatService
       ├── LocalizationManager (singleton)
       └── (other stores)
       
Views → ViewModels → [Stores | Services]
Services → BlueskySessionService → BlueskyRequestExecutor → URLSession
```

## 24. Key Architectural Decisions

1. **ObservableObject over @Observable macro**: Pre-dates iOS 17 @Observable; uses reference-type stores for more control over granularity of updates
2. **Manual DI over SwiftUI environment**: Explicit vs. implicit — `AppDependencies` creates all deps, injected via `.environmentObject()` at root
3. **Protocol-based services**: Enables `PreviewBlueskyClient` substitution for testing and previews
4. **In-memory session cache + Keychain persistence**: Balances performance (no Keychain read per request) with security (tokens not in UserDefaults)
5. **Composite WorkspaceStore**: `ModerationWorkspaceStore` aggregates three sub-stores to present a single interface to views
6. **Cursor-based pagination everywhere**: Follows AT Protocol conventions for consistent list loading patterns
7. **JSON localization over String Catalogs**: Manual JSON bundles with runtime switching, avoiding compile-time bindings
8. **Certificate pinning for bsky.social only**: Any PDS support means non-bsky.social hosts use standard TLS validation

## 25. Project Configuration

Generated by `xcodegen` from `project.yml`:
- Swift 6.0 with strict concurrency checking
- iOS 17.0 minimum deployment
- iPhone only (`TARGETED_DEVICE_FAMILY = "1"`)
- Portrait orientation only
- Face ID usage description configured
- Push notifications enabled
- Three targets: App, Unit Tests, UI Tests
