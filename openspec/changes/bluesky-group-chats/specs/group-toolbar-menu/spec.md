## ADDED Requirements

### Requirement: Group conversation detail toolbar provides group-specific actions
The toolbar in `ConversationDetailView` SHALL show an extended menu when the conversation `kind == .group`. The menu SHALL include:
- "Group Info" → opens `GroupInfoSheet`
- "Add Member" → opens add-member search sheet
- "Edit Name" → opens inline name editor
- Toggle lock/unlock (see `group-lock-toggle` spec)
- "Leave & Delete" → leaves the group (destructive, with confirmation)

For 1:1 conversations, the toolbar SHALL remain unchanged (mute/unmute, reload, delete).

#### Scenario: Group toolbar menu
- **WHEN** the user opens a group conversation and taps the toolbar menu
- **THEN** the menu shows: Group Info, Add Member, Edit Name, Lock/Unlock, Leave & Delete

#### Scenario: 1:1 toolbar unchanged
- **WHEN** the user opens a 1:1 DM conversation
- **THEN** the toolbar menu shows the existing actions (mute/unmute, reload, delete)

### Requirement: Leave group confirmation shows member count warning
When leaving a group conversation, the confirmation dialog SHALL display the number of remaining members and note that the action is irreversible.

#### Scenario: Leave group confirmation
- **WHEN** the user taps "Leave & Delete"
- **THEN** a confirmation dialog reads "Leave group? You will no longer see messages from this group. {N} members remain."
- **THEN** the user can confirm or cancel
