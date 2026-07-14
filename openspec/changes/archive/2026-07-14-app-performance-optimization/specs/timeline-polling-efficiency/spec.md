## ADDED Requirements

### Requirement: Timeline polling SHALL only run when the timeline tab is visible
The `FeedTimelineViewModel.startPolling()` method SHALL only execute its polling loop when the `FeedTimelineView` is on screen. Polling SHALL be suspended when the user navigates to another tab.

#### Scenario: Tab switch suspends polling
- **WHEN** the user switches from the Timeline tab to the Moderation tab
- **THEN** the polling task SHALL be cancelled within 1 second

#### Scenario: Return to timeline resumes polling
- **WHEN** the user switches back to the Timeline tab
- **THEN** polling SHALL resume with a fresh interval

#### Scenario: Polling not started for inactive feeds
- **WHEN** the timeline is not displayed at all (e.g., app launch on the Accounts tab)
- **THEN** the polling task SHALL NOT be started

### Requirement: Timeline polling interval SHALL adapt to app state
The polling interval SHALL be at least 15 seconds (reduced from 8 seconds) to reduce battery and network impact. When the user has been on the timeline for more than 2 minutes without interacting, the interval MAY increase to 30 seconds.

#### Scenario: Default polling interval
- **WHEN** the timeline becomes visible
- **THEN** polling SHALL run every 15 seconds

#### Scenario: Stale tab polling
- **WHEN** the user has been on the timeline for more than 2 minutes without scrolling or interacting
- **THEN** the polling interval SHALL increase to 30 seconds
