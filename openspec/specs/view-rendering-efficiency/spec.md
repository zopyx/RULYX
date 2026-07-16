# view-rendering-efficiency Specification

## Purpose
TBD - created by archiving change app-performance-optimization. Update Purpose after archive.
## Requirements
### Requirement: View bodies SHALL only invalidate on their specific data changes
SwiftUI views SHALL avoid full-body re-evaluation when unrelated state changes occur. View models SHALL use granular `@Observable` property observation where feasible rather than blanket `@Published` invalidation.

#### Scenario: Profile view model property change
- **WHEN** a single property of a view model changes (e.g., `isUpdatingModeration`)
- **THEN** only the subviews reading that property SHALL re-evaluate, not the entire view hierarchy

#### Scenario: ListsView count update
- **WHEN** `blockingCount` updates in `ListsViewModel`
- **THEN** only the count label subview SHALL re-render, not the entire list of moderation lists

### Requirement: Large scrollable lists SHALL use identity-based diffing
List rows in `RelationshipsView`, `ListsView`, and ALL timeline views (`FeedTimelineView`, `ListTimelineView`) SHALL use stable identifiers (`id: \\.post.uri` on `RichFeedEntry`) to minimize SwiftUI diffing cost.

#### Scenario: List insertion
- **WHEN** items are inserted into a timeline list
- **THEN** only the inserted rows SHALL animate/render, not the entire list

#### Scenario: Shared post row component avoids duplicate view hierarchies
- **WHEN** `TimelinePostRow` is used by both feed and list timelines
- **THEN** the view hierarchy for each post row SHALL be structurally identical, enabling SwiftUI to reuse rendering paths

### Requirement: BlueskyProfileView SHALL be decomposed
The 1841-line `BlueskyProfileView` body SHALL be decomposed into smaller named subviews/subview-builders to improve SwiftUI body diffing granularity and compile-time performance.

#### Scenario: Profile section toggles
- **WHEN** a profile section (e.g., owned lists) toggles visibility
- **THEN** only that section's subview SHALL re-evaluate, not the entire profile view

