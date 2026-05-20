# Rulyx — Project Guide for AI Agents

> Report issues: https://github.com/anomalyco/opencode/issues

## Project Overview
iOS-only SwiftUI app for Bluesky moderation (lists, bulk operations, profile inspection, followers/following management, timeline). Targets iOS 17+, runs on iPhone only (no iPad, no macOS). Uses xcodegen for project generation.

## Build & Test
```bash
xcodegen generate
xcodebuild -project RULYX.xcodeproj -scheme RULYX -destination 'generic/platform=iOS Simulator' build CODE_SIGNING_ALLOWED=NO
xcodebuild -project RULYX.xcodeproj -scheme RULYX -destination 'generic/platform=iOS Simulator' build-for-testing CODE_SIGNING_ALLOWED=NO
swiftformat --lint .
swiftlint
swiftformat Sources Tests
```

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
- **iPhone only** — TARGETED_DEVICE_FAMILY = "1" (runs in iPhone compatibility mode on iPad)
- **No macOS** — no Mac target, no Mac Catalyst
- **No iPad code paths** — do not use `horizontalSizeClass`, `NavigationSplitView`, or any iPad-adaptive layout branching; always use iPhone layout
- Do not add `#if os(macOS)` code paths

## Key Architecture
- **Services**: `BlueskyRequestExecutor`, `BlueskySessionService`, `BlueskyListService`, `BlueskyProfileService`, `LiveBlueskyClient`
- **Stores**: `ModerationWorkspaceStore`, `WorkspacePreferencesStore`, `ModerationAuditStore`, `ActionQueueStore`, `AccountStore`, `FeedStore`, `MutedWordsStore`, `AnalyticsStore`
- **Timeline**: `FeedTimelineViewModel`, `FeedTimelineView`, `FeedPickerView`, `TimelineTab`, `TimelineState`
- **Views**: SwiftUI with `@EnvironmentObject` injection via `AppDependencies`
- **Navigation**: `TabView` (5 tabs: Moderation, Info, Timeline, Settings, Accounts) with `NavigationStack` and `.navigationDestination`
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
