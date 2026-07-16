## Why

Bluesky's chat API already supports group conversations (multiple participants, group name, member management, lock/unlock, system events), and the RULYX app's data layer (models, DTOs, API service) is fully group-aware. However, the UI layer was built for 1:1 DMs and provides no way to create, manage, or interact with groups. Users can receive group messages and see group names, but cannot start a group, view its members, add/remove participants, edit the group name, or see a group info sheet. This limits RULYX to half the chat functionality Bluesky offers.

## What Changes

- **Multi-member conversation creation**: Extend `NewConversationSheet` to support selecting multiple members before creating a group
- **Group info sheet**: New sheet showing group name, member count, creation date, lock status, and full member list with avatars
- **Group member management**: UI to add members (search + select) and remove members (swipe or menu action, with confirmation for removing others)
- **Group name editing**: Inline editing of the group name via the group info sheet
- **Group lock/unlock**: Toggle in the group info sheet to lock/unlock the conversation (prevent new members)
- **Group avatar**: Generated group avatar using stacked member avatars or initials + member count badge
- **Conversation detail improvements**: Show member count and group indicator in the navigation bar for groups; add toolbar menu with "View Members" action
- **`ChatStore` enhancements**: `getOrCreateConvo` → `getConvoForMembers` supporting multiple DIDs; add `addMember`, `removeMember`, `updateGroupName`, `lockConvo`, `unlockConvo` methods
- **Localization**: Keys for all new UI strings (group creation, member management, info sheet)

## Capabilities

### New Capabilities

- `group-creation`: Multi-member selection sheet to create group conversations — search users, select multiple, create group via `chat.bsky.convo.getConvoForMembers`
- `group-info-sheet`: Dedicated sheet displaying group metadata (name, member count, lock status, created date) and full member list with avatars/handles
- `group-member-management`: Add members to an existing group (search + select sheet) and remove members (swipe-to-remove or menu action, with confirmation)
- `group-name-editing`: Inline rename of group conversations via an editable text field in the group info sheet
- `group-lock-toggle`: UI to lock (prevent new members) or unlock a group conversation, persisted via API
- `group-avatar`: Generated visual identifier for group conversations using stacked member avatars or initials + count badge
- `group-toolbar-menu`: Extended conversation detail toolbar for groups with "Members", "Add Member", "Edit Name", "Lock/Unlock", "Leave Group" actions

### Modified Capabilities

*(No existing specs are modified — these are entirely new UI capabilities on top of existing API infrastructure.)*

## Impact

| Area | Files | Change |
|------|-------|--------|
| **New Views** | `GroupInfoSheet.swift`, `AddMemberSheet.swift`, `GroupAvatarView.swift` | New SwiftUI components |
| **Modified Views** | `NewConversationSheet.swift`, `ConversationDetailView.swift`, `ConversationListView.swift` | Multi-select support, group-aware toolbars, group cell styling |
| **Store** | `ChatStore.swift` | Add `getOrCreateGroupConvo`, `addMember`, `removeMember`, `updateGroupName`, `lockConvo`, `unlockConvo` |
| **Service** | `ChatService.swift`, `ChatServicing.swift` | Add `addMember`, `removeMember`, `updateGroupName` API methods |
| **Localization** | `en.json` + 15 other language files | ~30 new keys for group UI |
| **Models** | `ChatModels.swift` | May need `ChatGroupInfo` fields for avatar generation (initials) |
