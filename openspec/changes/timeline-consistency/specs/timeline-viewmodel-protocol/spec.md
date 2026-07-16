## ADDED Requirements

### Requirement: TimelineViewModel protocol defines common contract
All timeline view models SHALL conform to the `TimelineViewModel` protocol, providing a consistent API for timeline consumers regardless of the underlying data source (main feed, list feed, or custom feed).

The protocol SHALL expose:
- `entries: [RichFeedEntry]` — all loaded posts
- `state: TimelineState` — unified loading/error/empty lifecycle
- `newPostCount: Int` — count of new posts since last refresh (0 if polling is inactive)
- `hasMore: Bool` — whether more pages can be loaded
- `isLoading: Bool` — whether initial load is in progress
- `loadTimeline(account:appPassword:using:)` — initial load
- `loadMore(account:appPassword:using:)` — pagination
- `refresh(account:appPassword:using:)` — pull-to-refresh
- `startPolling(account:appPassword:using:interval:)` / `stopPolling()` — lifecycle
- `userDidInteract()` — resets adaptive polling interval
- Optimistic interaction methods (`effectiveIsLiked`, `effectiveIsReposted`, `effectiveLikeCount`, `effectiveRepostCount`, `toggleLike`, `toggleRepost`)
- Inline thread methods (`toggleInlineThread`, `expandedThreadURIs`, `inlineThreads`)
- Lifecycle methods (`prepareForAccountChange`, `prepareForFeedChange`, `removeEntry`, `insertEntry`)

#### Scenario: FeedTimelineViewModel conforms
- **WHEN** `FeedTimelineViewModel` is checked against the protocol
- **THEN** it SHALL satisfy all protocol requirements without code changes beyond adding the conformance declaration

#### Scenario: ListTimelineViewModel conforms
- **WHEN** `ListTimelineViewModel` is refactored to use `TimelineState` and adopt the protocol
- **THEN** it SHALL satisfy all protocol requirements

#### Scenario: Consumer uses protocol-typed view model
- **WHEN** a SwiftUI view declares `var viewModel: any TimelineViewModel`
- **THEN** the view SHALL render identically regardless of which concrete implementation is injected

### Requirement: TimelineState is the single source of truth
All timeline view models SHALL use the `TimelineState` enum exclusively for lifecycle state. Individual boolean properties (`isLoading`, `isLoadingMore`, `hasMore`, `errorMessage`) SHALL NOT be used alongside or instead of `TimelineState`.

#### Scenario: ListTimelineViewModel migrated to TimelineState
- **WHEN** `ListTimelineViewModel` is refactored
- **THEN** `isLoading`, `isLoadingMore`, `hasMore`, and `errorMessage` properties are removed
- **THEN** all state queries go through `state` with computed properties (`state.isLoading`, `state.hasMore`, `state.errorMessage`)

#### Scenario: No boolean state flags remain
- **WHEN** checking any timeline view model
- **THEN** no ad-hoc boolean flags for loading/error/empty state exist outside `TimelineState`
