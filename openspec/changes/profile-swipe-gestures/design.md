## Context

The `RelationshipsView` handles all four relationship modes (Followers, Following, Blocking, Blocked by) in a single SwiftUI view. It currently offers:

- **Trailing swipe** → Block (`.swipeActions(edge: .trailing, allowsFullSwipe: false)`)
- **Context menu** → Block + Add to List
- **`.onDelete`** → Block (redundant, conflicts with swipe semantics)
- **No leading swipe** at all

The app already uses **both leading and trailing swipes** in `TimelinePostRow`, `UserPostsView`, and `ActionPresetsView`, establishing a pattern of dual swipe actions on interactive list rows.

The key architectural advantage: the `ListPickerSheet` component already exists and is used from the same view's context menu. Adding a leading swipe that presents the same sheet requires no new UI or services.

## Goals / Non-Goals

**Goals:**
- Add a consistent leading swipe (left-to-right) action to all four relationship modes in `RelationshipsView`
- Leading swipe opens the existing `ListPickerSheet` for adding the actor to a list
- Remove the redundant `.onDelete` modifier
- Keep trailing swipe Block behavior unchanged
- Keep context menu unchanged (still offers both Block + Add to List)

**Non-Goals:**
- Not adding new actions to the trailing swipe (it remains only Block)
- Not changing `BlueskyProfileActionsViewModel` or any service layer
- Not adding mode-specific swipe variants (same behavior in all four modes)
- Not changing iPad or any other list views' swipe behavior
- Not adding localization strings — all keys already exist

## Decisions

### Decision 1: Leading swipe triggers ListPickerSheet directly
- **Choice**: The leading swipe presents `ListPickerSheet` via existing `isShowingListPicker` state, same as the context menu
- **Rationale**: `ListPickerSheet` is already fully implemented, localized, and handles all list types (moderation, internal, curation). Reusing it avoids duplicating list-picking UI or state management.
- **Alternative considered**: Having the leading swipe show a quick-action menu with "Add to List" as the only option — adds unnecessary indirection.
- **Alternative considered**: Having mode-specific leading actions (e.g., "Unfollow" in Following mode) — increases complexity and breaks consistency across modes.

### Decision 2: `allowsFullSwipe: true` for leading, `false` for trailing
- **Choice**: Leading swipe uses `allowsFullSwipe: true` (action triggers on full swipe); trailing remains `allowsFullSwipe: false` (requires explicit tap)
- **Rationale**: Adding to a list is non-destructive and the ListPickerSheet serves as a natural confirmation point. Blocking is destructive, and the existing `confirmBlocks` preference requires the confirmation dialog.
- **Consistency**: Matches `TimelinePostRow` where leading swipe (Like) is full-swipe and trailing (Reply) also uses full-swipe — but block is a more sensitive action so we keep it `false`.

### Decision 3: Remove `.onDelete` modifier
- **Choice**: Delete the `.onDelete { ... }` modifier on the `ForEach` in RelationshipsView
- **Rationale**: `.onDelete` provides a system "Delete" swipe action with the default red trash icon, which is indistinguishable from the explicit trailing swipe Block action. Having both creates visual noise and the system swipe conflicts with the custom `.swipeActions` on the same row. The trailing `.swipeActions(edge: .trailing)` already covers the block action with better UX (custom label, icon, and `allowsFullSwipe: false`).

### Decision 4: No new localization keys needed
- **Choice**: Reuse existing `loc("rel.add_to_list")` for the leading swipe button label, `loc("rel.block")` for trailing, and all existing `loc("rel.*")` keys for confirmation dialogs
- **Rationale**: All required strings are already localized across all 16 language files
- **Verification**: `loc("rel.add_to_list")`, `loc("rel.block")`, `loc("rel.block_swipe.hint")`, `loc("actions.cancel")`, `loc("rel.block_confirm")`, `loc("rel.block_message")` all exist in the codebase

### Decision 5: ListPickerSheet not pre-loaded on swipe
- **Choice**: The `ListPickerSheet` loads its list data on `.task` when the sheet appears, not on swipe gesture start
- **Rationale**: Pre-loading on swipe would fire a network request every time the user swipes, even if they don't complete the action. Loading on sheet presentation keeps network usage minimal and matches the existing context-menu behavior.
- **Trade-off**: A slight delay (list fetch) after swipe vs. before swipe; acceptable since list fetching is fast (< 1s typically)

## Risks / Trade-offs

| Risk | Impact | Mitigation |
|------|--------|------------|
| Leading swipe gesture may conflict with `NavigationLink` tap | NavigationLink might intercept the swipe | SwiftUI handles swipe vs. tap natively; `.swipeActions` does not interfere with `.onTapGesture` or `NavigationLink`. Already proven in `ListDetailMembersSection` where swipe + NavigationLink coexist. |
| Full-swipe leading action may be too easy to trigger accidentally | User might accidentally open the list picker | Adding to a list requires a second tap in the sheet; the action isn't performed until the user picks a list. Accidental sheet dismissal has no side effects. |
| No mode-specific leading actions (e.g., Unfollow in Following mode) | Users might expect contextual leading actions | The proposal is about establishing a **consistent** pattern. Mode-specific variants can be added later as a separate change. |
| `.onDelete` removal may break `.onMove` if added later | Incompatible modifier usage | `.onDelete` and `.onMove` are independent; removing `.onDelete` doesn't affect ability to add `.onMove` for reordering. |

## Open Questions

- Should the leading swipe button use a `.tint(.blue)` to match the "Add to List" action in other contexts? Yes — match `ListDetailMembersSection` add-member patterns. Confirmed.
- Should there be an accessibility label on the leading swipe button? Yes — mirror the existing trailing swipe pattern with `.accessibilityHint`.
