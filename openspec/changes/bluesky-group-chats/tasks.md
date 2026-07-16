## 1. API Layer — Service additions

- [ ] 1.1 Add `addMember(convoId:memberDID:account:appPassword:)` to `ChatServicing` protocol
- [ ] 1.2 Add `removeMember(convoId:memberDID:account:appPassword:)` to `ChatServicing` protocol
- [ ] 1.3 Add `updateGroupName(convoId:name:account:appPassword:)` to `ChatServicing` protocol
- [ ] 1.4 Implement `addMember` in `ChatService` — POST to `chat.bsky.convo.addMember` with AT Protocol proxy header
- [ ] 1.5 Implement `removeMember` in `ChatService` — POST to `chat.bsky.convo.removeMember`
- [ ] 1.6 Implement `updateGroupName` in `ChatService` — POST to `chat.bsky.convo.updateName`
- [ ] 1.7 Add DTO types (`AddMemberResponse`, `RemoveMemberResponse`, `UpdateNameResponse`) if needed
- [ ] 1.8 Verify build — all new service methods compile

## 2. Store Layer — ChatStore group operations

- [ ] 2.1 Add `getOrCreateGroupConvo(memberDIDs: [String])` — calls `getConvoForMembers` with multiple DIDs
- [ ] 2.2 Add `addMember(convoId:memberDID:)` — calls service + updates local state
- [ ] 2.3 Add `removeMember(convoId:memberDID:)` — calls service + updates local state
- [ ] 2.4 Add `updateGroupName(convoId:name:)` — calls service + updates local `groupInfo.name`
- [ ] 2.5 Add `ChatLocalAction.groupInfoUpdated` case for local state propagation after group changes
- [ ] 2.6 Wire `ChatLocalAction.reloadConvos` after member add/remove to refresh conversation list
- [ ] 2.7 Verify build — store compiles with all new methods

## 3. Group Avatar Component

- [ ] 3.1 Create `GroupAvatarView` — generated avatar from `[ChatMemberProfile]`
- [ ] 3.2 Implement avatar stacking: 1 member → single image, 2 → side-by-side, 3–4 → 2×2 grid, 5+ → 2×2 grid with +N badge
- [ ] 3.3 Implement fallback: no avatars → group name initials (or "G") centered in a circle
- [ ] 3.4 Add `GroupAvatarView` as a reusable component accessible from both conversation list and detail view
- [ ] 3.5 Wire `ConversationRowView` to show `GroupAvatarView` for `.kind == .group`
- [ ] 3.6 Wire `ConversationDetailView` navigation bar to show group avatar + name + member count subtitle for groups
- [ ] 3.7 Verify build + preview

## 4. Multi-Member Conversation Creation

- [ ] 4.1 Update `NewConversationSheet` to support multi-select: add `selectedActors: Set<BlueskyActor>`, toggle checkmarks on tap
- [ ] 4.2 Add selected-count badge in toolbar area (e.g., "3 selected")
- [ ] 4.3 Change confirmation button label: "Start Chat" for 1 selection, "Create Group" for ≥2, disabled for 0
- [ ] 4.4 Update `startConversation` to call `getOrCreateGroupConvo` when ≥2 members selected
- [ ] 4.5 Update `ChatStore.getOrCreateConvo` to accept optional multiple DIDs (or create new `getOrCreateGroupConvo`)
- [ ] 4.6 Verify creation flow for both 1:1 DM and group conversation
- [ ] 4.7 Verify build

## 5. Group Info Sheet

- [ ] 5.1 Create `GroupInfoSheet` as a `NavigationStack`-wrapped sheet
- [ ] 5.2 Display group name (with edit button — wire to task 6.x), member count, creation date, lock status with toggle (wire to task 7.x)
- [ ] 5.3 Display full member list using `LazyVStack` with `ForEach` — avatar, display name, handle
- [ ] 5.4 Add swipe-to-remove on member rows (calls `chatStore.removeMember` with confirmation)
- [ ] 5.5 Add tap-to-view-profile on member rows
- [ ] 5.6 Wire entry point in `ConversationDetailView` toolbar menu (group context)
- [ ] 5.7 Verify build + preview

## 6. Group Name Editing

- [ ] 6.1 Add inline editing mode to `GroupInfoSheet` — tap group name to enter text field
- [ ] 6.2 Add "Save" and "Cancel" buttons in editing mode
- [ ] 6.3 Wire save to `chatStore.updateGroupName(convoId:name:)`
- [ ] 6.4 Show system message preview in conversation after rename
- [ ] 6.5 Verify build

## 7. Group Lock/Unlock

- [ ] 7.1 Add lock/unlock toggle to `GroupInfoSheet` — `Toggle` or button with lock icon
- [ ] 7.2 Confirmation dialog for locking ("Lock this group? No new members can be added.")
- [ ] 7.3 Wire to `chatStore.muteConvo` / `chatStore.unmuteConvo` or dedicated lock API calls
- [ ] 7.4 Handle permanent lock state — disable toggle with explanatory text
- [ ] 7.5 Verify build

## 8. Conversation Detail Toolbar for Groups

- [ ] 8.1 Extend `ConversationDetailView` toolbar to show group-specific menu when `conversation.kind == .group`
- [ ] 8.2 Menu items: Group Info, Add Member, Edit Name, Lock/Unlock, Leave & Delete
- [ ] 8.3 "Add Member" action opens `AddMemberSheet` (task 10.x)
- [ ] 8.4 "Leave & Delete" shows confirmation with member count, calls `chatStore.leave`
- [ ] 8.5 Keep existing 1:1 toolbar unchanged (mute/unmute, reload, delete)
- [ ] 8.6 Verify build

## 9. Add Member Sheet

- [ ] 9.1 Create `AddMemberSheet` — search for Bluesky actor (reuses `container.profile.searchActors`)
- [ ] 9.2 Single-selection (tap to select, confirm button to add)
- [ ] 9.3 Wire to `chatStore.addMember(convoId:memberDID:)`
- [ ] 9.4 Dismiss sheet on success
- [ ] 9.5 Verify build

## 10. Localization

- [ ] 10.1 Add all new localization keys to `en.json`:
  - `chat.group.create` / `chat.group.start` — button labels
  - `chat.group_info.title` / `chat.group_info.members` / `chat.group_info.created` / `chat.group_info.locked` / `chat.group_info.unlocked`
  - `chat.add_member.title` / `chat.add_member.placeholder` / `chat.add_member.success`
  - `chat.remove_member.confirm` / `chat.leave_group.confirm`
  - `chat.lock.confirm` / `chat.lock.locked` / `chat.lock.unlocked` / `chat.lock.permanent`
  - `chat.edit_name.save` / `chat.edit_name.cancel`
- [ ] 10.2 Add keys (English fallback) to all 15 non-English language files (de.json, fr.json, es.json, pt.json, etc.)
- [ ] 10.3 Verify `make lint` passes (localization key sync check)

## 11. Verification

- [ ] 11.1 Build project: `xcodebuild -project RULYX.xcodeproj -scheme RULYX -destination 'platform=iOS Simulator' build CODE_SIGNING_ALLOWED=NO`
- [ ] 11.2 Run `make lint` — SwiftFormat + SwiftLint pass
- [ ] 11.3 Manual test: create 1:1 DM (verify no regression)
- [ ] 11.4 Manual test: create group with 3 members (verify group created, members visible)
- [ ] 11.5 Manual test: view group info sheet (verify metadata + member list)
- [ ] 11.6 Manual test: add/remove member (verify system messages appear)
- [ ] 11.7 Manual test: edit group name (verify name updates everywhere)
- [ ] 11.8 Manual test: lock/unlock group (verify toggle + inability to add members when locked)
- [ ] 11.9 Manual test: leave group (verify conversation disappears from list)
- [ ] 11.10 Validate OpenSpec: `openspec validate bluesky-group-chats --json`
