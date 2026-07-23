# universal-follow-badges Specification

## Purpose
TBD - created by archiving change universal-follow-badges. Update Purpose after archive.
## Requirements
### Requirement: Follow-status badges in all member-list contexts
Every member-list context in the app SHALL display "Following" (blue pill) and "Follows me" (green pill) badges below the member's handle, consistent with the existing implementation in list detail views.

#### Scenario: Badge appears when current user follows the member
- **WHEN** a member list is displayed (relationships, search results, comparison, profile search)
- **AND** the current user follows that member (viewerState.isFollowing == true)
- **THEN** a blue "Following" pill badge SHALL appear below the member's handle

#### Scenario: Badge appears when member follows current user
- **WHEN** a member list is displayed
- **AND** the member follows the current user (viewerState.followsYou == true)
- **THEN** a green "Follows me" pill badge SHALL appear below the member's handle

#### Scenario: Both badges appear when bi-directional follow
- **WHEN** a member list is displayed
- **AND** both conditions are true
- **THEN** both "Following" and "Follows me" badges SHALL appear side by side

### Requirement: Double-tap to follow/unfollow in member lists
Every member-list context in the app SHALL support double-tap to follow/unfollow a member with optimistic UI feedback, consistent with the existing implementation in list detail views.

#### Scenario: Double-tap to follow
- **WHEN** user double-taps a member row
- **AND** the current user does NOT already follow that member
- **THEN** the "Following" badge SHALL appear immediately (optimistic update)
- **AND** a follow API call SHALL be dispatched in the background
- **AND** on success, the badge SHALL remain visible
- **AND** on failure, the badge SHALL revert

#### Scenario: Double-tap to unfollow
- **WHEN** user double-taps a member row
- **AND** the current user already follows that member
- **THEN** the "Following" badge SHALL disappear immediately (optimistic update)
- **AND** an unfollow API call SHALL be dispatched in the background
- **AND** on success, the badge SHALL remain hidden
- **AND** on failure, the badge SHALL reappear

### Requirement: Viewer state carried through actor data model
The `BlueskyActor` model SHALL carry an optional `viewerState: BlueskyViewerState?` field so that follow-relationship data is available in all member-list contexts without requiring separate API calls.

#### Scenario: Viewer state populated from API responses
- **WHEN** followers/following are fetched via `getFollowers`/`getFollows`
- **THEN** the `viewer` field from the API response SHALL be mapped to `BlueskyActor.viewerState`

#### Scenario: Viewer state populated from actor search
- **WHEN** actors are fetched via `searchActors`/`searchActorsTypeahead`
- **THEN** the `viewer` field from the API response SHALL be mapped to `BlueskyActor.viewerState`

### Requirement: Reusable follow-badge component
A reusable SwiftUI view component SHALL encapsulate the "Following"/"Follows me" badge rendering, accepting a `BlueskyViewerState?` and returning the appropriate pill badges.

#### Scenario: Shared component used in all contexts
- **WHEN** any member list renders a row
- **THEN** it SHALL use the shared badge component rather than duplicating badge layout code

