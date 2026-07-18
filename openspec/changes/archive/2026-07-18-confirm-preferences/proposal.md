## Why

Users want finer control over confirmation dialogs for destructive actions — blocking and unfollowing. When performing bulk moderation or trusted workflows, repeated confirmations slow down the user. Two new preferences allow users to skip block and unfollow confirmations entirely.

## What Changes

- **New Settings toggles** "Confirm blocks" and "Confirm unfollow" in the Moderation section of Settings (both default ON)
- **Block confirmation** in `RelationshipsView` is skipped when "Confirm blocks" is OFF
- **Unfollow confirmation** is ADDED in `BlueskyProfileView` when "Confirm unfollow" is ON
- **Block likers confirmation** in `PostLikerActionsManager` is skipped when "Confirm blocks" is OFF

## Capabilities

### New Capabilities
- `confirm-preferences`: User-configurable confirmation dialogs for block and unfollow actions

### Modified Capabilities
- None

## Impact

- `Sources/App/SettingsView.swift` — Add two @AppStorage toggles in Moderation section
- `Sources/Features/Lists/RelationshipsView.swift` — Gate block confirmation on `confirmBlocks` pref
- `Sources/Features/Lists/BlueskyProfileView.swift` — Add unfollow confirmation dialog
- `Sources/Features/Lists/BlueskyProfileViewModel.swift` — Support unfollow confirmation
- `Sources/Shared/Components/Posts/PostLikerActionsManager.swift` — Gate block likers confirmation
- `Sources/Shared/Localizations/en.json` + 15 files — New localization keys
