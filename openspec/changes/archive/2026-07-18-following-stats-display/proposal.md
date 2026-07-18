## Why

Users need to quickly identify accounts in their following list that have zero posts (potentially inactive/bot accounts) and see social stats (posts, followers, following counts) at a glance without tapping into each profile individually.

## What Changes

- **Filter toggle** "No posts only" below the search field in "My Followings" view — when active, only shows followed accounts with zero posts
- **Stats row** showing "X posts · Y followers · Z following" as an additional row below each actor's description in "My Followings"
- **Show/Hide toggle** for the stats row in the toolbar menu (same pattern as existing "Show Descriptions"), only visible for the Followings mode
- **Batch stat fetching** via existing `LiveBlueskyClient.fetchProfileStats` after the following list loads

## Capabilities

### New Capabilities
- `following-stats-display`: Display and toggle post/follower/following stats for followed accounts, plus a filter for accounts with no posts

### Modified Capabilities
- None

## Impact

- `Sources/Domain/Models/BlueskyActor.swift` — Add optional stats properties
- `Sources/Features/Lists/RelationshipsView.swift` — Add stats fetching, filter UI, stats row rendering, menu toggle
- `Sources/Shared/Localizations/en.json` + 15 other language files — New localization keys
