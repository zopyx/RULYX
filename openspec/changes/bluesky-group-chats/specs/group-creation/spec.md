## ADDED Requirements

### Requirement: New conversation sheet supports multi-member selection
The `NewConversationSheet` SHALL allow users to search for and select multiple Bluesky actors before creating a conversation. When a single member is selected, a 1:1 DM is created. When two or more members are selected, a group conversation is created.

The multi-select UI SHALL:
- Show a checkmark for each selected actor in the search results list
- Display a count badge in the toolbar (e.g., "3 selected")
- Allow deselecting by tapping a selected row
- Use "Create Group" as the confirmation button title when ≥2 members are selected

#### Scenario: Single member creates DM
- **WHEN** the user searches for and selects exactly one actor
- **THEN** the confirmation button reads "Start Chat"
- **WHEN** the user taps confirm
- **THEN** a 1:1 DM conversation is created via `getOrCreateConvo`

#### Scenario: Multiple members creates group
- **WHEN** the user selects two or more actors
- **THEN** a selected count is displayed (e.g., "3 selected")
- **THEN** the confirmation button reads "Create Group"
- **WHEN** the user taps confirm
- **THEN** a group conversation is created via `getConvoForMembers` with all selected DIDs

#### Scenario: Deselect removes member
- **WHEN** the user taps an already-selected actor row
- **THEN** that actor is deselected and the checkmark is removed
- **WHEN** selections drop below 2
- **THEN** the button reverts to "Start Chat" (or is disabled with 0 selections)

### Requirement: ChatStore supports multi-member conversation creation
`ChatStore` SHALL provide a method `getOrCreateGroupConvo(memberDIDs: [String])` that calls `ChatService.getConvoForMembers(members:account:appPassword:)` with multiple DIDs.

#### Scenario: Group creation API call
- **WHEN** `getOrCreateGroupConvo(memberDIDs: [did1, did2, did3])` is called
- **THEN** the service calls `chat.bsky.convo.getConvoForMembers` with all three DIDs
- **THEN** the returned conversation is added to the local conversations list and navigated to
