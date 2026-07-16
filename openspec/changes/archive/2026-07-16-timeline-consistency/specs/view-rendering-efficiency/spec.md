## MODIFIED Requirements

### Requirement: Large scrollable lists SHALL use identity-based diffing
List rows in `RelationshipsView`, `ListsView`, and ALL timeline views (`FeedTimelineView`, `ListTimelineView`) SHALL use stable identifiers (`id: \\.post.uri` on `RichFeedEntry`) to minimize SwiftUI diffing cost.

#### Scenario: List insertion
- **WHEN** items are inserted into a timeline list
- **THEN** only the inserted rows SHALL animate/render, not the entire list

#### Scenario: Shared post row component avoids duplicate view hierarchies
- **WHEN** `TimelinePostRow` is used by both feed and list timelines
- **THEN** the view hierarchy for each post row SHALL be structurally identical, enabling SwiftUI to reuse rendering paths
