## Why

The RelationshipsView (covering Followers, Following, Blocking, Blocked by) currently implements only a **trailing swipe to Block** — there is no leading swipe action at all. Other list views in the app (TimelinePostRow, UserPostsView, ActionPresetsView) already use **both leading and trailing swipe actions** as a pattern. The member profile lists are inconsistent with this established UI convention, missing the opportunity for quick, ergonomic access to common actions like Add to List or Mute without tapping through a profile or context menu.

This proposal defines a consistent two-swipe gesture scheme for member profile lists, aligned with the app's existing swipe patterns and the HIG for iOS swipe actions (primary/positive on leading, destructive/menu on trailing).

## What Changes

- **RelationshipsView**: Add a **leading swipe action** (left-to-right) for all four modes (Followers, Following, Blocking, Blocked by)
- **Existing trailing swipe** (Block): Kept as-is, but behavior/documentation clarified per mode
- **`.onDelete` modifier**: Removed — it redundantly duplicates the trailing-swipe Block and adds no value; the swipe action and context menu already cover blocking
- **New leading action for all modes**: "Add to List" — quickly adds the actor to a moderation/curation/internal list, mirroring the existing context menu item
- **Mode-specific trailing behavior**: The trailing-swipe Block action is consistent across all four modes, but confirmation dialog copies reflect the specific mode (blocking a follower vs. blocking someone you follow)
- **Consistency alignment**: The swipe action behavior matches the existing `allowsFullSwipe: false` pattern for destructive/trailing actions and uses `allowsFullSwipe: true` for the leading (non-destructive) action

## Capabilities

### New Capabilities
- `leading-swipe-add-to-list`: Leading swipe action on member profile rows that opens the list picker sheet, allowing quick addition of an actor to a moderation/curation/internal list without navigating to the profile

### Modified Capabilities
- *(No existing spec changes — this is purely an implementation improvement within the existing RelationshipsView; no requirement-level behavior changes to archived specs)*

## Impact

- **Files modified**: `Sources/Features/Lists/RelationshipsView.swift` — add leading swipe action, remove `.onDelete`, confirm dialog copy alignment
- **No API changes**: All actions (block, add to list) already exist via `BlueskySocialService` and `ListPickerSheet`
- **No new dependencies**: Uses existing `ListPickerSheet`, `confirmBlocks` preference, and `BlueskyProfileActionsViewModel`
- **No localization impact**: All strings already localized via the existing `loc("rel.*")` keys
