## Why

List detail views (iPhone + iPad) already show "Following" (blue) and "Follows me" (green) badges with double-tap follow/unfollow. Other member-list contexts — relationships (followers/following/blocking/blockedBy), user search, custom search, profile inspector, and list comparison — still lack this functionality, creating an inconsistent UX where users must navigate to a profile view to see or change follow status.

## What Changes

- **RelationshipsView** (followers/following/blocking/blockedBy): Add follow-status badges to each row + double-tap to follow/unfollow
- **UserSearchSheet**: Add follow-status badges + double-tap follow/unfollow to search results
- **CustomSearchView** (Users tab): Add follow-status badges + double-tap follow/unfollow
- **ProfileInspectorView** (search results): Add follow-status badges + double-tap follow/unfollow
- **ListDetailComparisonSection**: Add follow-status badges to comparison bucket members
- **Data model**: Add optional `viewerState` to `BlueskyActor` to carry follow-state through all contexts

## Capabilities

### New Capabilities
- `universal-follow-badges`: Follow-status badges (Following/Follows me) and double-tap follow/unfollow in all member-list contexts throughout the app

### Modified Capabilities
*(none — no existing specs change behavior)*

## Impact

- `BlueskyActor.swift` — add optional `viewerState` field
- `BlueskyProfileService.swift` — map viewer state in followers/following/search API responses
- `RelationshipsView.swift` — add badges + double-tap (the largest change)
- `UserSearchSheet.swift` — add badges + double-tap
- `CustomSearchView.swift` — add badges + double-tap to users tab
- `ProfileInspectorView.swift` — add badges to search result rows
- `ListDetailComparisonSection.swift` — add badges to comparison bucket rows
- Localization keys for new badge strings (may reuse existing keys)
