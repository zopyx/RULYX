# Rulyx — Project Guide for AI Agents

> Report issues: https://github.com/anomalyco/opencode/issues

## Project Overview
iOS SwiftUI app for Bluesky moderation (lists, bulk operations, profile inspection, followers/following management, timeline). Targets iOS 17+, runs on iPhone and iPad (adaptive layout via `horizontalSizeClass`). No macOS. Uses xcodegen for project generation.

## Build & Test
```bash
xcodegen generate
xcodebuild -project RULYX.xcodeproj -scheme RULYX -destination 'generic/platform=iOS Simulator' build CODE_SIGNING_ALLOWED=NO
xcodebuild -project RULYX.xcodeproj -scheme RULYX -destination 'generic/platform=iOS Simulator' build-for-testing CODE_SIGNING_ALLOWED=NO
swiftformat --lint .
swiftlint
swiftformat Sources Tests
```

## Screenshots (App Store)

### Quick start
```bash
# 1. Create .env in project root with your Bluesky credentials:
#    export TEST_HANDLE=yourhandle.bsky.social
#    export TEST_PASSWORD=your-app-password
#    export TEST_PDS=https://bsky.social     # optional, defaults to bsky.social

# 2. Run (uses fastlane + snapshot)
make screenshots

# 3. Resize (run separately if fastlane's resize lane fails)
bundle exec fastlane ios resize_screenshots  # or:
# for f in screenshots/en-US/*.png; do b=n=${f%.*}; [[ "$b" != *_1260x2736 ]] && sips -z 2736 1260 "$f" --out "${b}_1260x2736.png"; done
```

### How it works

**Test structure** (`UITests/ScreenshotTests.swift`):
- `testCaptureCoreTabs` — launches without beta features, captures Moderation, Timeline, Chat, Info, Settings, Accounts (6 always-visible tabs)
- `testCaptureBetaTabs` — launches with `-showBetaFeatures 1`, captures Moderation, Timeline, Notifications, Chat (beta tabs include Notifications)

iOS tab bars show at most 5 tabs before placing extras in a "More" list, so the two tests split the 7 total tabs cleanly.

**Credential sources** (priority order):
1. Environment variables `TEST_HANDLE` / `TEST_PASSWORD` / `TEST_PDS`
2. `.env` file in project root (supports `export KEY=VALUE` and `KEY=VALUE` formats, strips single/double quotes)
3. If neither is set → falls back to `PreviewBlueskyClient` + preview accounts (mock data)

**Launch flow** (when credentials are provided):
1. `ScreenshotTests.setUp()` passes credentials via `app.launchEnvironment` and `--test-account` argument
2. `AppDependencies.init()` switches from `PreviewBlueskyClient` to `LiveBlueskyClient` and from `AccountStore(preview:)` to `AccountStore(keychain:)`
3. `RULYXApp.swift` runs a `.task` that calls `accountStore.addAccount()` with the credentials, authenticating against the live API
4. `sleep(3)` in the test gives the auth call time to complete before screenshots begin

**Key files:**
| File | Role |
|------|------|
| `UITests/ScreenshotTests.swift` | XCTest test methods, credential loading, `.env` parser |
| `UITests/SnapshotHelper.swift` | Fastlane's standard screenshot helper (writes to `~/Library/Caches/tools.fastlane/screenshots/`) |
| `fastlane/Snapfile` | Device ("iPhone 16 Pro Max"), language ("en-US"), output dir |
| `fastlane/Fastfile` | `screenshots` lane (capture + resize to 1260×2736) |
| `Sources/App/AppDependencies.swift` | Detects `--test-account`, uses `LiveBlueskyClient` + real `AccountStore` |
| `Sources/App/RULYXApp.swift` | `.task` that adds the test account on launch |

**Known issues:**
- `testAccountDetailNavigation` (`RULYXUITests.swift:149`) fails when `--test-account` is used because it expects preview account "team-alpha.bsky.social". Screenshot tests still pass and screenshots are collected because `stop_after_first_error: false` in the Fastfile.
- `setup_simulator_env` in the Fastfile's `before_all` block is not defined, causing `resize_screenshots` lane to error when invoked independently. Run the manual `sips` resize command above.

## Navigation Design Guide

### Toolbar Button Rules

| Role | Visual | Placement | Component |
|------|--------|-----------|-----------|
| Dismiss / Close | `xmark.circle.fill` | `.topBarTrailing` | `ToolbarCloseButton()` |
| Confirm / Save | Localized text | `.confirmationAction` | `Button(loc("actions.save"))` |
| Cancel | Localized text | `.cancellationAction` | `Button(loc("actions.cancel"))` |
| Create / Add | `plus` | `.topBarTrailing` | Inline button |
| Search | `magnifyingglass` | `.topBarLeading` | Inline button |

**Key rules:**
- Dismiss buttons use `xmark.circle.fill` (via `ToolbarCloseButton`) — never `checkmark.circle.fill`
- Dismiss buttons go in `.topBarTrailing` — never `.confirmationAction` (reserved for form submit)
- All icon-only buttons MUST have `.accessibilityLabel(loc("..."))`
- All toolbar titles use `.toolbarTitleDisplayMode(.inline)` (not the deprecated `.navigationBarTitleDisplayMode`)

### Reusable Components

- **`ToolbarCloseButton`** (`Sources/Shared/Components/StatePanels.swift`): Dismiss/close button with `xmark.circle.fill`. Use for all sheet dismissals. Supports optional `action:` for custom close logic (e.g., `ToolbarCloseButton(action: { showSheet = false })`).
- **`HelpInfoButton`** (`Sources/Shared/Components/StatePanels.swift`): Info button with `info.circle.fill`, opens a `.sheet` with explanation text. Always placed right of a section header label.

### Pull-to-Refresh vs Refresh Button

- Views with `.refreshable` (pull-to-refresh) **must not** have a dedicated `arrow.clockwise` reload button
- Only keep `arrow.clockwise` in views that lack `.refreshable`

### Navigation Titles

- Always use `.toolbarTitleDisplayMode(.inline)` (iOS 18+ API)
- Suppress title (`.navigationTitle("")`) only when the view provides its own visual title via a section header or `.principal` toolbar item

## Platform Constraints
- **iPhone + iPad** — TARGETED_DEVICE_FAMILY = "1,2" (runs natively on both, adaptive via `horizontalSizeClass`)
- **No macOS** — no Mac target, no Mac Catalyst
- **iPad navigation** — uses `NavigationSplitView` (sidebar + content column) in regular width; falls back to iPhone TabView in compact (Slide Over / 1/3 split)
- **iPad views** live in `Sources/App/iPad/` and `Sources/Features/*/iPad/` directories
- **iPhone views** remain untouched — all iPad views are new files; branching happens at `RootView` level via `horizontalSizeClass`
- Do not add `#if os(macOS)` code paths

## iPad Architecture

### Navigation
- `RootView` checks `horizontalSizeClass`: regular → `iPadRootView()`, compact → existing `TabView`
- `iPadRootView` uses `NavigationSplitView` with `iPadSidebar` (list) and content column
- Sidebar sections: Moderation, Search & Profiles, Social (beta-gated), System
- All 7 original tabs are accessible as sidebar items; content column renders the corresponding view
- `iPadDashboardView` uses a responsive `LazyVGrid` layout

### Keyboard Shortcuts
- Defined via `.commands` builder in `RULYXApp.swift` (Mac-style menu bar for iPadOS)
- Shortcuts: Cmd+L (Lists), Cmd+D (Dashboard), Cmd+F (Search), Cmd+T (Timeline), etc.
- Navigation via `NotificationCenter.default.post(name: .iPadNavigateTo, object:)`

### Multi-Window
- `WindowGroup("Profile", for: String.self)` opens standalone profile windows
- `ProfileWindowView` fetches actor by DID and renders `BlueskyProfileView`

### Files
| File | Role |
|------|------|
| `Sources/App/iPad/iPadRootView.swift` | Root split view, sidebar + content dispatch |
| `Sources/App/iPad/iPadSidebar.swift` | Sidebar with sectioned lists, beta gating |
| `Sources/App/iPad/iPadNavigationState.swift` | Selection state for sidebar/columns |
| `Sources/App/iPad/iPadDashboardView.swift` | Grid dashboard with charts |
| `Sources/App/iPad/iPadEmptyDetailPlaceholder.swift` | Empty state when no detail selected |
| `Sources/App/iPad/iPadMentionsSearchWrapper.swift` | Placeholder for mentions search (profile-required) |
| `Sources/App/iPad/iPadCommandPalette.swift` | Cmd+K quick action palette with fuzzy search |
| `Sources/App/iPad/iPadDragDrop.swift` | TransferableActor/List + drag source modifier |
| `Sources/App/iPad/iPadKeyboardShortcuts.swift` | Centralized shortcut registry |
| `Sources/App/iPad/iPadListsView.swift` | Two-column list browser (content column) |
| `Sources/App/iPad/iPadListDetailView.swift` | Detail column list member viewer + actions |
| `Sources/App/iPad/iPadProfileInspector.swift` | Detail column profile card with tabs |
| `Sources/App/iPad/iPadTimelineView.swift` | Timeline wrapper for iPad content column |
| `Sources/App/iPad/iPadNotificationsView.swift` | Notifications wrapper for iPad content column |
| `Sources/App/iPad/iPadChatView.swift` | Chat wrapper for iPad content column |

## Key Architecture
- **Services**: `BlueskyRequestExecutor`, `BlueskySessionService`, `BlueskyListService`, `BlueskyProfileService`, `LiveBlueskyClient`
- **Stores**: `ModerationWorkspaceStore`, `WorkspacePreferencesStore`, `ModerationAuditStore`, `ActionQueueStore`, `AccountStore`, `FeedStore`, `MutedWordsStore`, `AnalyticsStore`
- **Timeline**: `FeedTimelineViewModel`, `FeedTimelineView`, `FeedPickerView`, `TimelineTab`, `TimelineState`
- **Views**: SwiftUI with `@EnvironmentObject` injection via `AppDependencies`
- **Navigation (iPhone)**: `TabView` (7 tabs: Moderation, Timeline, Notifications, Chat, Info, Settings, Accounts) with `NavigationStack` and `.navigationDestination`
- **Navigation (iPad)**: `NavigationSplitView` with sidebar (all 7 sections as sidebar items) — accessible via root `horizontalSizeClass` branching
- **DI**: All dependencies created in `AppDependencies` and injected as environment objects

## Task Documentation Requirement
Every completed task MUST include an accurate description rendered as a table:

| Area | Change | Impact |
|------|--------|--------|
| Files modified | List of files | What was done and why |

## Coding Conventions
- Swift 6 with strict concurrency (`@MainActor` where needed)
- `Sendable` conformance on model types
- AppError for normalized error handling
- Logger via `AppLogger` (search, persistence, moderation, performance categories)
- Project generated with `xcodegen` from `project.yml` — never edit `.pbxproj` directly
- Views in `Sources/Features/Lists/`, `Sources/Features/Profile/`, `Sources/Features/Accounts/`, `Sources/Features/Timeline/`
- Services in `Sources/Domain/Services/`
- Models in `Sources/Domain/Models/`
- Timeline state managed via `TimelineState` enum (not boolean flags)

## Internationalization (i18n) Architecture

### Core — `LocalizationManager` (`Sources/Shared/Localizations/LocalizationManager.swift`)
- `@MainActor` `ObservableObject` singleton accessed via `LocalizationManager.shared`
- Global free function `loc(_ key: String) -> String` calls `LocalizationManager.shared.localized(key)`
- All views inject it as `@EnvironmentObject private var localizationManager: LocalizationManager`
- `AppDependencies` sets `localizationManager = LocalizationManager.shared`

### How it works
- **16 JSON files** in `Sources/Shared/Localizations/` (`en.json`, `de.json`, `fr.json`, `it.json`, `ja.json`, `zh.json`, `es.json`, `pt.json`, `ko.json`, `ru.json`, `ar.json`, `nl.json`, `pl.json`, `tr.json`, `th.json`, `vi.json`)
- All bundles are loaded eagerly in `init()` via `loadAll()` — reads each JSON file from `Bundle.main`, decodes as `[String: String]`, stored in `allBundles: [String: [String: String]]`
- Active language bundle held in `bundle: [String: String]`, swapped by `loadCurrentBundle()`

### Language selection & fallback chain
1. **User-selected** language stored in `UserDefaults.standard.string(forKey: "selectedLanguage")`
2. If no saved selection → **preferred device language** (if in `supportedLanguages`)
3. If no match → **English** (`"en"`)
4. If key missing in active bundle → **English bundle** (100% coverage guaranteed)
5. If missing in English bundle → **raw key string** returned

### RTL support
- Arabic (`"ar"`) sets `layoutDirection: LayoutDirection = .rightToLeft`
- All other languages use `.leftToRight`
- Used by views to flip layout via `.environment(\.layoutDirection, localizationManager.layoutDirection)`

### String parameters
- **No Swift-native `String(format:)` or `String.LocalizationValue` interpolation** — uses manual `replacingOccurrences(of: "{n}")` pattern
- Example: JSON key `"time.minutes_ago": "{n} minutes ago"` → `loc(key).replacingOccurrences(of: "{n}", with: "\(minutes)")`

### Relative dates
- Relative date formatting for older items (≥28 days) uses `DateFormatter` with `.medium` date style
- No locale override — defaults to system locale; relative formatters in some views explicitly use `Locale(identifier: LocalizationManager.shared.currentLanguage)`

### Key naming convention
- Dot-notation: `screen.component.description` (e.g., `"onboarding.moderation.desc"`, `"settings.language"`)
- Key-value pairs flat in JSON (no nesting)

### Localization API — One System Only
- **All** string lookups MUST use the custom `LocalizationManager` via one of:
  - `loc("key")` (global free function, returns `String`)
  - `String.localized("key")` (convenience static, supports `replacements:`)
  - `Text(loc: "key")` (custom `Text` initializer)
  - `.navigationTitle(loc: "key")` / `.accessibilityLabel(loc: "key")` / `.accessibilityHint(loc: "key")` (custom view modifiers)
- **Never** use Apple's native `String(localized:)`, `LocalizedStringResource`, or `LocalizedStringKey` — these bypass the in-app language setting and read the device system language instead, causing language mismatches when the user's in-app selection differs from the device language.

### Adding new keys
- All user-facing strings MUST use `loc("key")` — never hardcode English text
- Every new key must be added to **all 16 language files**
- New keys in non-English files require **native translation** — do not leave English fallback

## Blocking / Blocked-By Consistency
- Dashboard blocking count (`fetchBlockingCount`/`fetchBlockedByCount`) and detail view count (`fetchBlockedActors`/`fetchBlockedByActors`) MUST come from the **same source** — the paginated Clearsky API (`fetchClearskyActors`), NOT the `/total/` endpoint
- This ensures the number shown on the dashboard always matches the number in the RelationshipsView detail list

## Blocking / Blocked-By List Item Layout
In `RelationshipsView`, each blocking/blocked-by list item uses this two-row layout:

```
Row 1: Display Name_____________3 days ago
Row 2: @handle
```

## Secret Storage — Keychain over UserDefaults
- **Bluesky passwords/sessions**: `KeychainService` (`Sources/Domain/Services/KeychainService.swift`) using Security framework
- **Klipy API key**: Also stored in Keychain via `KeychainService` (same `com.ajung.RULYX.klipy` service, `apiKey` account)
- **No secrets in UserDefaults** — the old `UserDefaults.standard.string(forKey: "klipyAPIKey")` pattern is deprecated; migration runs in `GIFService.init()` to move any leftover key to Keychain
- **View helper**: `KlipyKeychainHelper` enum in `GIFService.swift` provides `read()`, `save(_:)`, `exists()` for views that need to check/display API key status

## HTTP Debug & URL Sanitization
- `HTTPRequestDebugStore` logs all HTTP request URLs for debugging in `HTTPRequestDebugView`
- URLs containing API keys (Klipy pattern `https://api.klipy.com/api/v1/{key}/...`) are **automatically redacted** via `sanitizeURL()` in `HTTPRequestDebugStore.begin()` — the key segment is replaced with `[REDACTED]` before storage

## GIF Service (Klipy)
- `GIFService` (`Sources/Domain/Services/GIFService.swift`) singleton for GIF search/trending via Klipy API
- API key embedded in URL path: `{baseURL}/{apiKey}/gifs/search?q=...`
- Key stored in Keychain, seeded on first launch via `seedKeyIfNeeded()` in `init()`
- No settings UI to configure the key — it's pre-seeded and hidden
- `GIFPickerView` (`Sources/Shared/Components/GIFPickerView.swift`) uses a manual `TextField` search bar (not `.searchable()`) pinned above the image grid for always-visible search

## ModerationSplitView
- Now a thin wrapper that always delegates to `ListsView` — no `NavigationSplitView`, no `horizontalSizeClass` branching
- Used from `RootView` TabView for the Moderation tab

## Preferred Search Account
- **Storage**: `AccountStore.preferredSearchAccountID` (`UUID?`) persisted in UserDefaults under `bluesky.preferredSearchAccountID`
- **Setting UI**: `AccountTabView` (Accounts tab) — displays a `Menu` listing all accounts; selection sets `accountStore.preferredSearchAccountID = account.id`
- **Fallback**: When no preference is set or the preferred account is deleted → falls back to `accountStore.activeAccount`
- **Deletion handling**: When the preferred account is removed, `AccountStore.removeAccount()` resets it to `accounts.first?.id`
- **Search views** (`CustomSearchView`, `MentionsSearchView`): On first appearance, read `preferredSearchAccountID` and set local `searchAccount` state. No inline account switching UI — the search account is purely driven by the global preference set in the Accounts tab
- **Account row in search forms**: Displays the preferred search account's **avatar** and display name as a static info row (not interactive), showing which account is being used for searches

## Account Context — Which Account for Which Operation

The app distinguishes between **read/search** operations (use `preferredSearchAccount`) and **write/mutation** operations (use `activeAccount`). This separation ensures data discovery uses the configured search perspective while moderation actions always execute as the currently active account.

### Profile Detail View (`BlueskyProfileView`)

| Category | Operation | Account |
|----------|-----------|---------|
| **Read** | Viewer state (blocking/muting badges) | `activeAccount` (the acting user's relationship with the profile) |
| **Read** | Profile inspection | `viewerAccount` (`activeAccount`) |
| **Read** | List memberships (which lists contain this profile) | `dataAccount` (`preferredSearchAccount` → `activeAccount`) |
| **Read** | Owned lists (lists the profile created) | `searchAccount` (`preferredSearchAccount`) |
| **Read** | Subscribed moderation lists | `searchAccount` (`preferredSearchAccount`) |
| **Read** | Media counts | `dataAccount` (`preferredSearchAccount`) |
| **Read** | ClearSky lists | No account (public API) |
| **Read** | Handle audit log | No account (public API) |
| **Write** | Toggle block / mute / follow | `activeAccount` |
| **Write** | Toggle list membership | `activeAccount` |
| **Write** | Create list + add actor | `activeAccount` |
| **Write** | Block back | `activeAccount` |

**How it works in code:**
- `content(account:appPassword:)` receives `activeAccount` → all mutation closures inside use `account`
- `dataAccount = preferredSearchAccount ?? activeAccount` is used for data-loading calls (`load`, `loadIfNeeded`)
- `load(did:account:viewerPassword:dataAccount:dataPassword:)` splits viewer state (active) from data (preferred search)
- `.task(id:)` sets `searchAccount = preferredSearchAccount` for owned/subscribed list fetches

### Search Views (`CustomSearchView`, `MentionsSearchView`, `MediaBrowserView`)

| Operation | Account |
|-----------|---------|
| Search queries | `preferredSearchAccount` (falls back to `activeAccount`) |
| Media fetching | `preferredSearchAccount` (falls back to `activeAccount`) |

**How it works in code:**
- On first appear, reads `accountStore.preferredSearchAccountID` and sets local `searchAccount`
- No inline account switching — preference set globally in Accounts tab

### Compose / Post Views (`ComposePostView`, `FeedTimelineView`)

| Operation | Account |
|-----------|---------|
| Creating posts | `activeAccount` |
| Editing posts (delete + recreate) | `activeAccount` |
| Reply / quote | `activeAccount` |

### Account Manager (`AccountTabView`)

| Operation | Account |
|-----------|---------|
| Switching accounts | `activeAccount` (set by switch) |
| Adding accounts | `activeAccount` (newly added) |
| Setting preferred search | Account selected in `Menu` |

**Empty state rule:** When `accountStore.accounts.isEmpty`, the view MUST show a visible "Add Account" button (`.buttonStyle(.borderedProminent)`). A `ContentUnavailableView` alone is insufficient — users need a tappable action to add the first account.
