## Context

The app currently has varying confirmation patterns for destructive actions:
- Block in RelationshipsView: has a confirmation dialog (.confirmationDialog)
- Block in BlueskyProfileView: no confirmation (direct toggle via `toggleBlock`)
- Block in PostLikerActionsManager: has a confirmation alert
- Unfollow anywhere: no confirmation (direct toggle via `toggleFollow`)

## Goals / Non-Goals

**Goals:**
- Add two @AppStorage preferences (`confirmBlocks` and `confirmUnfollow`, both default true)
- Add toggles in Settings → Moderation section
- Gate existing block confirmations behind `confirmBlocks`
- Add unfollow confirmation behind `confirmUnfollow`
- Add localization keys for all new UI strings

**Non-Goals:**
- Not changing batch operations (BatchOperationProgressView has its own progress-based flow)
- Not changing block-back flow (already has multi-step confirmation)
- Not changing mute toggle (no confirmation exists or requested)
- Not changing post/account report flows

## Decisions

### Preference storage: @AppStorage in each view vs centralized
- **Decision**: Use `@AppStorage` in each view that needs it (standard UserDefaults-backed pattern, consistent with existing `@AppStorage("debugMode")`, `@AppStorage("showActorDescriptions")` etc.)
- **Rationale**: Consistent with existing pattern, zero refactoring needed. Each view reads the pref independently from UserDefaults.
- **Alternative considered**: Centralized SettingsStore → overkill for two booleans

### Unfollow confirmation: BlueskyProfileView vs BlueskyProfileViewModel
- **Decision**: Add confirmation dialog in `BlueskyProfileView` before calling `viewModel.toggleFollow()`, since the view owns the UI/presentation layer
- **Rationale**: `BlueskyProfileViewModel.toggleFollow` is a pure action method. Adding presentation logic (confirmations) to the view model violates separation of concerns. The view controls the confirmation sheet/dialog lifecycle.

### Block confirmation in PostLikerActionsManager
- **Decision**: Gate `showBlockLikersConfirmation` behind `confirmBlocks` pref inside `handleBlockAllLikers`. When pref is off, call `confirmBlockLikers` directly.
- **Rationale**: This is the point where the confirmation is triggered — clean single-point change.

## Risks / Trade-offs

- The PostRowCallbacks block (from post context menus) and FeedTimelineView block remain without any confirmation path regardless of preferences. Adding confirmations there would be a larger UX change.
