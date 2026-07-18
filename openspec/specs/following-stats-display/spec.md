# following-stats-display Specification

## Purpose
TBD - created by archiving change following-stats-display. Update Purpose after archive.
## Requirements
### Requirement: Filter followed accounts with no posts
The system SHALL provide a filter toggle in the "My Followings" view to show only accounts that have zero posts.

#### Scenario: Enabling filter hides accounts with posts
- **WHEN** the user taps the "No posts only" toggle in the search section
- **THEN** only followed accounts with `postsCount == 0` are displayed in the list

#### Scenario: Disabling filter shows all accounts
- **WHEN** the user disables the "No posts only" toggle
- **THEN** all followed accounts are displayed again

#### Scenario: Filter is only available in Following mode
- **WHEN** the user is viewing Followers, Blocking, or Blocked By modes
- **THEN** the "No posts only" filter SHALL NOT be displayed

#### Scenario: Filter requires stats data
- **WHEN** stats have not finished loading
- **THEN** the filter toggle SHALL be disabled until stats are available

### Requirement: Display stats row for followed accounts
The system SHALL display a stats row showing posts, followers, and following counts for each followed account when the "Show Stats" toggle is enabled.

#### Scenario: Stats row visible when showStats is enabled
- **GIVEN** a followed account with known stats
- **WHEN** "Show Stats" is enabled in the toolbar menu
- **THEN** the row displays "{posts} posts · {followers} followers · {following} following" below the actor's description/handle

#### Scenario: Stats row hidden when showStats is disabled
- **WHEN** "Show Stats" is disabled in the toolbar menu
- **THEN** the stats row SHALL NOT be displayed for any account

#### Scenario: Stats row only in Following mode
- **WHEN** the user is viewing Followers, Blocking, or Blocked By modes
- **THEN** the stats row SHALL NOT be displayed

#### Scenario: Stats loaded asynchronously after following list
- **GIVEN** the following list has loaded
- **THEN** the system SHALL call `LiveBlueskyClient.fetchProfileStats` with all followed DIDs to fetch stats in the background

### Requirement: Stats visibility toggle in toolbar menu
The system SHALL provide a "Show Stats" toggle in the toolbar menu (same section as "Show Descriptions") that is only visible in the Following mode.

#### Scenario: Toggle appears in Following mode
- **WHEN** the user opens the toolbar menu in the "My Followings" view
- **THEN** the menu SHALL contain a "Show Stats" toggle

#### Scenario: Toggle is hidden in other modes
- **WHEN** the user opens the toolbar menu in Followers, Blocking, or Blocked By views
- **THEN** the menu SHALL NOT contain a "Show Stats" toggle

#### Scenario: Toggle persists across sessions
- **WHEN** the user enables "Show Stats" and navigates away
- **THEN** the preference SHALL be persisted via `@AppStorage("showActorStats")`

