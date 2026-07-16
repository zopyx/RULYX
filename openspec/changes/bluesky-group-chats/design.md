## Context

The Bluesky Chat API (`chat.bsky.convo.*`) supports group conversations natively. RULYX already has:

- **Models**: `ChatConversationKind.group`, `ChatGroupInfo` (name, memberCount, createdAt, lockStatus), `ChatSystemMessageData.editGroup`, `ChatMemberProfile`
- **DTOs**: `ConvoKindUnion` (discriminated union for direct/group), `GroupConvoDTO` (name, memberCount, createdAt, lockStatus)
- **Service**: `ChatServicing` protocol + `ChatService` with `getConvoForMembers(members:)` (already accepts array), list/get/send message/leave/mute/unmute/log
- **Store**: `ChatStore` manages conversations, messages, event log processing, polling, push notifications
- **Views**: `ConversationListView` (conversation list with search), `ConversationDetailView` (message list + send bar + toolbar), `NewConversationSheet` (single-member creation), `ChatMessageBubble`, `ChatStatusBanner`

**What's missing** is the user-facing UI for group-specific actions. The data layer is ready; the UI layer only supports 1:1 DMs.

## Existing API Endpoints Reference

| Endpoint | Purpose | Status |
|----------|---------|--------|
| `chat.bsky.convo.listConvos` | List conversations | ✅ Implemented |
| `chat.bsky.convo.getConvo` | Get single conversation | ✅ Implemented |
| `chat.bsky.convo.getConvoForMembers` | Find/create by member list | ✅ Implemented (accepts `[String]`) |
| `chat.bsky.convo.getMessages` | Get messages in a conversation | ✅ Implemented |
| `chat.bsky.convo.sendMessage` | Send a text message | ✅ Implemented |
| `chat.bsky.convo.updateRead` | Mark as read | ✅ Implemented |
| `chat.bsky.convo.leaveConvo` | Leave conversation | ✅ Implemented |
| `chat.bsky.convo.muteConvo` / `unmuteConvo` | Mute/unmute notifications | ✅ Implemented |
| `chat.bsky.convo.getLog` | Event log for polling | ✅ Implemented |
| `chat.bsky.convo.addMember` | Add member to group | ❌ Not implemented |
| `chat.bsky.convo.removeMember` | Remove member from group | ❌ Not implemented |
| `chat.bsky.convo.updateName` | Update group name | ❌ Not implemented |

## Goals / Non-Goals

**Goals:**
- Full group conversation creation (multi-member selection)
- Group info sheet with member list and metadata
- Add/remove group members
- Edit group name inline
- Lock/unlock group
- Generated group avatar
- Group-specific toolbar actions

**Non-Goals:**
- Group admin roles (deferred until API supports role information)
- Message reactions beyond current support (already works for all message types)
- Group-specific push notifications (existing infrastructure handles this)
- Group search/filter in conversation list (already works via group name/last message)
- Video/voice calls in groups

## Architecture Decisions

### 1. Group creation reuses existing API endpoint

**Decision**: Group creation uses the existing `chat.bsky.convo.getConvoForMembers` with multiple DIDs — the Bluesky API already handles creating a group when ≥2 members are provided.

**Rationale**: No new API endpoint needed. The `ChatServicing.getConvoForMembers(members:)` already accepts `[String]`. The store layer just needs a convenience method.

### 2. New sheets for group info and member management

**Decision**: Create `GroupInfoSheet`, `AddMemberSheet` as dedicated SwiftUI views rather than adding members/actions inline.

**Rationale**: Group info contains enough data (member list, metadata, lock status) to justify a full sheet. Inline member management would overcrowd the toolbar.

### 3. Group avatar as `@ViewBuilder` component

**Decision**: `GroupAvatarView` is a pure SwiftUI `View` that takes `members: [ChatMemberProfile]` and renders stacked member avatars or a fallback letter. No external image processing library needed.

**Fallback strategy**: 1 avatar → single image, 2 → side-by-side, 3–4 → 2×2 grid, 5+ → 2×2 grid with +N badge. No avatars available → group name initials (or "G" for unnamed) centered in a circle.

### 4. Group lock toggle with confirmation

**Decision**: Locking requires confirmation (destructive, irreversible via UI). Unlocking does not (can be re-locked). Permanently locked groups (status `"permanent"` or `"locked"`) disable the toggle entirely.

### 5. API layer additions

**Decision**: Add four new methods to `ChatServicing` / `ChatService`:
- `addMember(convoId:memberDID:account:appPassword:)` → `chat.bsky.convo.addMember`
- `removeMember(convoId:memberDID:account:appPassword:)` → `chat.bsky.convo.removeMember`
- `updateGroupName(convoId:name:account:appPassword:)` → `chat.bsky.convo.updateName`
- Lock/unlock reuse existing `lockConvo` / `unlockConvo` methods (already implemented)

### 6. Localization strategy

**Decision**: All new UI strings follow existing `chat.*` key prefix convention:
- `chat.group.*` for group-specific labels
- `chat.group_info.*` for info sheet
- `chat.add_member.*` for member management
- New keys added to all 16 language files (keys only — translations TBD)

## Risks / Trade-offs

| Risk | Mitigation |
|------|------------|
| **`chat.bsky.convo.addMember/removeMember/updateName` may not exist in AT Protocol yet** | Verify API endpoints before implementation. If missing, speculatively implement with correct signatures and stub responses — release notes clarify pending API support. |
| **Group member count can be large (hundreds)** | Member list uses `LazyVStack` for lazy rendering. "Add Member" search uses debounced API search (matching existing search pattern). |
| **Permanent lock cannot be undone** | UI clearly distinguishes regular lock (toggleable) from permanent lock (no toggle possible). Confirmation dialog for locking explains consequences. |
| **Existing `NewConversationSheet` UX changes** | Multi-select reuses the same search sheet. A selected state indicator + confirmation button label change is a minimal UX change. Users creating DMs see no difference (single selection works identically). |
| **ChatLocalAction enum needs new cases** | Add `.groupInfoUpdated(convoId:groupInfo:)` for local state updates after name changes, member changes. |

## Open Questions

1. **Does `chat.bsky.convo.getConvoForMembers` with >2 members create a group conversation or fail?** Needs API verification. If it does not support multi-member creation, a separate endpoint may be needed.
2. **Does the API return member roles (admin vs member)?** If not, the role indicator requirement is deferred. The UI can treat all members equally.
3. **What happens when a group has only 2 members after removing all but one?** Should it auto-convert to a 1:1 DM? Likely yes, but this is an edge case to defer.
4. **Does `chat.bsky.convo.leaveConvo` work for groups?** If leaving a group deletes the entire conversation (vs removing just the current user), additional handling is needed.
