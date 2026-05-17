# Rulyx — Project Guide for AI Agents

## Project Overview
iOS-only SwiftUI app for Bluesky moderation (lists, bulk operations, profile inspection, followers/following management, timeline). Targets iOS 17+, runs on iPhone only (no iPad, no macOS). Uses xcodegen for project generation.

## Build & Test
```bash
xcodegen generate
xcodebuild -project BlueskyModeration.xcodeproj -scheme BlueskyModeration -destination 'generic/platform=iOS Simulator' build CODE_SIGNING_ALLOWED=NO
xcodebuild -project BlueskyModeration.xcodeproj -scheme BlueskyModeration -destination 'generic/platform=iOS Simulator' build-for-testing CODE_SIGNING_ALLOWED=NO
swiftformat --lint .
swiftlint
swiftformat Sources Tests
```

## Platform Constraints
- **iPhone only** — TARGETED_DEVICE_FAMILY = "1"
- **No iPad support** — no iPad-specific code, no iPad orientations
- **No macOS** — no Mac target, no Mac Catalyst
- Do not add `#if os(macOS)` or iPad-only code paths

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

## Internationalization (i18n)
- All user-facing strings MUST use `loc("key")` — never hardcode English text
- Translation keys follow dot-notation: `screen.component.description`
- All 16 language files must be updated when adding new keys:
  `en.json`, `de.json`, `fr.json`, `it.json`, `ja.json`, `zh.json`,
  `es.json`, `pt.json`, `ko.json`, `ru.json`, `ar.json`, `nl.json`,
  `pl.json`, `tr.json`, `th.json`, `vi.json`
- New keys in non-English files require native translation — do not leave English fallback

## Blocking / Blocked-By Consistency
- Dashboard blocking count (`fetchBlockingCount`/`fetchBlockedByCount`) and detail view count (`fetchBlockedActors`/`fetchBlockedByActors`) MUST come from the **same source** — the paginated Clearsky API (`fetchClearskyActors`), NOT the `/total/` endpoint
- This ensures the number shown on the dashboard always matches the number in the RelationshipsView detail list

## Blocking / Blocked-By List Item Layout
In `RelationshipsView`, each blocking/blocked-by list item uses this two-row layout:

## Blocking / Blocked-By List Item Layout
In `RelationshipsView`, each blocking/blocked-by list item uses this two-row layout:

```
Row 1: Display Name_____________3 days ago
Row 2: @handle
```
