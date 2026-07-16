## MODIFIED Requirements

### Requirement: Timeline polling SHALL only run when the timeline tab is visible
The timeline view model's `startPolling()` method SHALL execute its polling loop when the corresponding timeline view is on screen. Polling SHALL be suspended when the user navigates away. This requirement now applies to ALL timeline views, not just `FeedTimelineView`.

#### Scenario: Tab switch suspends polling
- **WHEN** the user switches from the Timeline tab to the Moderation tab
- **THEN** the polling task for the main feed SHALL be cancelled within 1 second

#### Scenario: Return to timeline resumes polling
- **WHEN** the user switches back to the Timeline tab
- **THEN** polling SHALL resume with a fresh interval

#### Scenario: Polling not started for inactive feeds
- **WHEN** a timeline is not displayed at all
- **THEN** the polling task SHALL NOT be started

#### Scenario: List timeline polling stops on dismiss
- **WHEN** a list timeline view is dismissed (sheet close or navigation pop)
- **THEN** its polling task SHALL be cancelled

### Requirement: Timeline polling interval SHALL adapt to app state
The polling interval SHALL be at least 15 seconds to reduce battery and network impact. When the user has been on the timeline for more than 2 minutes without interacting, the interval SHALL increase to 30 seconds. This applies to ALL polling-capable timelines.

#### Scenario: Default polling interval
- **WHEN** any timeline becomes visible and polling starts
- **THEN** polling SHALL run every 15 seconds

#### Scenario: Stale tab polling
- **WHEN** the user has been on the timeline for more than 2 minutes without scrolling or interacting
- **THEN** the polling interval SHALL increase to 30 seconds

#### Scenario: List timeline interaction resets interval
- **WHEN** the user scrolls or interacts with a list timeline
- **THEN** the polling interval SHALL reset to 15 seconds
