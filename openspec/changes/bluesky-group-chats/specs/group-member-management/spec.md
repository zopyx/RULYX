## ADDED Requirements

### Requirement: Users can add members to an existing group conversation
The conversation detail view SHALL provide an "Add Member" action that opens a search sheet. The user searches for a Bluesky actor and selects them. The selected member SHALL be added to the group via the API (`chat.bsky.convo.addMember`).

#### Scenario: Add member succeeds
- **WHEN** the user taps "Add Member" and selects an actor
- **THEN** the actor is added to the group
- **THEN** a system message "Member added" appears in the conversation
- **THEN** the member list in the group info sheet updates

#### Scenario: Add member to locked group
- **WHEN** the group is locked
- **THEN** the "Add Member" action is disabled or hidden
- **THEN** an explanation tooltip reads "Group is locked — no new members can be added"

### Requirement: Users can remove members from a group
The group info sheet SHALL allow removing members via swipe action or a context menu. Removing a member SHALL call `chat.bsky.convo.removeMember` via the API. A confirmation dialog SHALL be shown before removal ("Remove @user from the group?").

#### Scenario: Remove member
- **WHEN** the user swipes to delete a member in the group info sheet
- **THEN** a confirmation dialog is shown
- **WHEN** confirmed
- **THEN** the member is removed from the group via API
- **THEN** a system message "Member removed" appears

#### Scenario: Cannot remove self via remove member
- **WHEN** viewing the group info sheet
- **THEN** the current user SHALL NOT show a remove action (use "Leave Group" instead)

### Requirement: ChatStore supports add/remove member API calls
`ChatStore` SHALL provide `addMember(convoId:memberDID:)` and `removeMember(convoId:memberDID:)` methods that call the corresponding API endpoints and update the local state (member list, system message insertion, conversation list refresh).

#### Scenario: Add member updates local state
- **WHEN** `addMember` completes successfully
- **THEN** the local conversation's `members` array is updated
- **THEN** conversations list is reloaded (via `reloadConvos` local action)

#### Scenario: Remove member updates local state
- **WHEN** `removeMember` completes successfully
- **THEN** the member is removed from the local members array
- **THEN** conversations list is reloaded
