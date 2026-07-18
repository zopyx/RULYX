## ADDED Requirements

### Requirement: Settings toggles for confirmations
The system SHALL provide two toggle preferences in Settings → Moderation: "Confirm blocks" and "Confirm unfollow", both defaulting to ON.

#### Scenario: Confirm blocks toggle defaults to ON
- **GIVEN** the user opens Settings for the first time
- **THEN** the "Confirm blocks" toggle SHALL be enabled by default

#### Scenario: Confirm unfollow toggle defaults to ON
- **GIVEN** the user opens Settings for the first time
- **THEN** the "Confirm unfollow" toggle SHALL be enabled by default

#### Scenario: Toggle persists across app restarts
- **WHEN** the user changes a confirmation toggle and restarts the app
- **THEN** the preference SHALL be retained

### Requirement: Block confirmation gated by preference
The system SHALL skip the block confirmation dialog when "Confirm blocks" is disabled.

#### Scenario: Block without confirmation when pref is OFF
- **GIVEN** "Confirm blocks" is disabled in Settings
- **WHEN** the user triggers a block action in the following/followers lists
- **THEN** the block SHALL execute immediately without a confirmation dialog

#### Scenario: Block likers without confirmation when pref is OFF
- **GIVEN** "Confirm blocks" is disabled in Settings
- **WHEN** the user selects "Block all likers" from a post context menu
- **THEN** the block-all-likers operation SHALL start immediately without a confirmation dialog

### Requirement: Unfollow confirmation gated by preference
The system SHALL show a confirmation dialog before unfollowing when "Confirm unfollow" is enabled, and skip it when disabled.

#### Scenario: Unfollow shows confirmation when pref is ON (default)
- **GIVEN** "Confirm unfollow" is enabled
- **WHEN** the user toggles the follow button for an account they currently follow
- **THEN** a confirmation dialog SHALL appear asking "Unfollow this account?"

#### Scenario: Unfollow without confirmation when pref is OFF
- **GIVEN** "Confirm unfollow" is disabled
- **WHEN** the user toggles the follow button for an account they currently follow
- **THEN** the unfollow SHALL execute immediately without a confirmation dialog
