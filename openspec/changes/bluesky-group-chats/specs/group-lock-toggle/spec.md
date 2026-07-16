## ADDED Requirements

### Requirement: Group lock status is toggleable from the group info sheet
The group info sheet SHALL display the current lock status and provide a toggle to lock or unlock the group. Locking a group prevents new members from being added. The toggle SHALL call `chat.bsky.convo.lockConvo` or `chat.bsky.convo.unlockConvo` via the API.

#### Scenario: Lock group
- **WHEN** the user taps the lock toggle (currently showing "Unlocked")
- **THEN** a confirmation dialog is shown ("Lock this group? No new members can be added.")
- **WHEN** confirmed
- **THEN** `lockConvo` is called via the API
- **THEN** the status updates to "Locked"
- **THEN** a system message "Conversation locked" appears in the chat

#### Scenario: Unlock group
- **WHEN** the user taps the lock toggle (currently showing "Locked")
- **THEN** `unlockConvo` is called via the API (no confirmation needed for unlocking)
- **THEN** the status updates to "Unlocked"
- **THEN** a system message "Conversation unlocked" appears

#### Scenario: Permanently locked groups cannot toggle
- **WHEN** `lockStatus` is "permanently locked"
- **THEN** the lock toggle is disabled with a lock icon and explanatory text
