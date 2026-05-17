# Rulyx

iOS-only SwiftUI app for Bluesky moderation. Manage lists, inspect profiles, browse followers/following, and read your timeline.

## Requirements

- iOS 17+
- iPhone only (no iPad, no Mac)
- Xcode 16+
- [xcodegen](https://github.com/yonaskolb/XcodeGen)

## Setup

```bash
xcodegen generate
open BlueskyModeration.xcodeproj
```

## Build

```bash
xcodegen generate
xcodebuild -project BlueskyModeration.xcodeproj -scheme BlueskyModeration -destination 'generic/platform=iOS Simulator' build CODE_SIGNING_ALLOWED=NO
```

## Architecture

- **5 tabs**: Moderation, Info, Timeline, Settings, Accounts
- **DI**: `AppDependencies` creates all services/stores, injected via `@EnvironmentObject`
- **State**: `ObservableObject` stores with `@Published` properties
- **Localization**: 16 languages via JSON files, accessed through `loc("key")`

## Timeline Feature

The timeline is a first-class tab with:
- Account-scoped feed selection
- URI-based new post detection
- `TimelineState` enum for explicit state management
- Skeleton loading, error/empty states with retry
- Sentinel-based pagination
- Recent feeds tracking
- Mute word shortcut from post context menu
