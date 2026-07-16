# list-timeline-polling Specification

## Purpose
TBD - created by archiving change timeline-consistency. Update Purpose after archive.
## Requirements
### Requirement: List timelines support adaptive polling
`ListTimelineViewModel` SHALL support periodic background polling for new posts using the same adaptive interval strategy as `FeedTimelineViewModel`.

The polling system SHALL:
- Start at a 15-second base interval
- Back off to 30 seconds after 120 seconds without user interaction
- Reset to 15 seconds when `userDidInteract()` is called
- Track known post URIs via `knownURIs: Set<String>`
- Increment `newPostCount` for each new URI discovered
- Not poll during `.initialLoading` state or when `knownURIs` is empty

#### Scenario: Polling discovers new list posts
- **WHEN** polling is active and a member of the list creates a new post
- **THEN** `newPostCount` SHALL increment and the "N new posts" banner SHALL appear

#### Scenario: Polling backs off without interaction
- **WHEN** 120 seconds pass without `userDidInteract()` being called
- **THEN** the polling interval SHALL increase from 15s to 30s

#### Scenario: Polling resets on interaction
- **WHEN** `userDidInteract()` is called after a back-off period
- **THEN** the polling interval SHALL reset to 15 seconds

#### Scenario: Polling stops on disappear
- **WHEN** the list timeline view disappears
- **THEN** polling SHALL be cancelled via `stopPolling()`

