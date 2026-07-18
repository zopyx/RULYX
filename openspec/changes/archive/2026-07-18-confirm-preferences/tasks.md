## 1. Settings UI

- [ ] 1.1 Add `@AppStorage("confirmBlocks")` and `@AppStorage("confirmUnfollow")` to SettingsView
- [ ] 1.2 Add two toggle rows in Moderation section

## 2. RelationshipsView — Block Confirmation Gate

- [ ] 2.1 Add `@AppStorage("confirmBlocks")` property
- [ ] 2.2 Check pref before setting `isShowingBlockConfirm = true` — block directly when disabled

## 3. BlueskyProfileView — Unfollow Confirmation

- [ ] 3.1 Add `@AppStorage("confirmUnfollow")` and `@AppStorage("confirmBlocks")` properties
- [ ] 3.2 Add confirmation dialog for unfollow when pref is ON
- [ ] 3.3 Guard the follow/unfollow toggle action

## 4. PostLikerActionsManager — Block Likers Gate

- [ ] 4.1 Gate `showBlockLikersConfirmation` behind `confirmBlocks` pref

## 5. Localization

- [ ] 5.1 Add `settings.confirm_blocks`, `settings.confirm_unfollow`, `rel.unfollow_confirm` keys to en.json
- [ ] 5.2 Add keys to all other 15 language files

## 6. Build & Verify

- [ ] 6.1 Run `xcodegen generate` and build
- [ ] 6.2 Run swiftlint and swiftformat
