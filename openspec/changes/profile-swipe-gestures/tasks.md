## 1. Review Current State & Understand Existing Code

- [ ] 1.1 Verify the current swipe action implementation in `RelationshipsView.swift` — confirm the trailing swipe, context menu, and `.onDelete` arrangement around line 216
- [ ] 1.2 Verify the `ListPickerSheet` is fully functional and reusable — confirm it uses `selectedActorForList` and `isShowingListPicker` state
- [ ] 1.3 Confirm all localization keys exist: `loc("rel.add_to_list")`, `loc("rel.block")`, `loc("rel.block_swipe.hint")`

## 2. Add Leading Swipe Action

- [ ] 2.1 Add `.swipeActions(edge: .leading, allowsFullSwipe: true)` to the member row in `RelationshipsView`, positioned **before** the existing trailing swipe modifier
- [ ] 2.2 Implement the leading swipe button: label with `loc("rel.add_to_list")` and `Image(systemName: "list.bullet")`, `.tint(.blue)`, with `.accessibilityHint(loc: "rel.add_to_list.hint")`
- [ ] 2.3 Wire the leading swipe button's action to set `selectedActorForList = actor` and `isShowingListPicker = true` (identical to the context menu item)

## 3. Remove Redundant .onDelete Modifier

- [ ] 3.1 Remove the `.onDelete { indexSet in ... }` modifier from the `ForEach` in `RelationshipsView.swift` (around line 230)
- [ ] 3.2 Verify no `.onDelete`-dependent warnings or compilation errors remain

## 4. Verify & Polish

- [ ] 4.1 Build the project: `xcodebuild -project RULYX.xcodeproj -scheme RULYX -destination 'generic/platform=iOS Simulator' build CODE_SIGNING_ALLOWED=NO`
- [ ] 4.2 Run SwiftLint: `swiftlint` — no new warnings or errors from the changed file
- [ ] 4.3 Run SwiftFormat: `swiftformat Sources/Features/Lists/RelationshipsView.swift` — ensure formatting is consistent
- [ ] 4.4 Run `openspec validate --change profile-swipe-gestures --json` to verify completeness
