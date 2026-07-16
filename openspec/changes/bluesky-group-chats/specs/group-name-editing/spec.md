## ADDED Requirements

### Requirement: Group name is editable inline
The group info sheet SHALL allow editing the group name via a text field. A "Save" button SHALL persist the new name via the API (`chat.bsky.convo.updateName` or similar endpoint). A "Cancel" button SHALL discard the change.

#### Scenario: Edit group name
- **WHEN** the user taps the group name in the group info sheet
- **THEN** the name becomes editable (text field)
- **WHEN** the user changes the name and taps "Save"
- **THEN** the API is called to persist the change
- **THEN** the conversation list updates to show the new name
- **THEN** a system message "Group renamed to {new name}" appears in the conversation

#### Scenario: Cancel edit
- **WHEN** the user edits the group name but taps "Cancel"
- **THEN** the original name is restored
- **THEN** no API call is made

### Requirement: ChatService supports group name updates
`ChatServicing` SHALL add a method `updateGroupName(convoId:name:account:appPassword:)` that calls `chat.bsky.convo.updateName` with the new group name.

#### Scenario: Name update API call
- **WHEN** `updateGroupName` is called with a valid name
- **THEN** the API is called and the conversation's `groupInfo.name` is updated in the local store
