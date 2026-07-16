## ADDED Requirements

### Requirement: Views adapt to horizontal/vertical size class
All views that currently have iPad-specific variants SHALL instead use `@Environment(\.horizontalSizeClass)` and `@Environment(\.verticalSizeClass)` to adjust their internal layout. No separate `iPad*` wrapper views SHALL exist.

Adaptive rules:
- **Dashboard**: In regular width, show 3+ columns of cards (`LazyVGrid` with `.adaptive(minimum: 300)`). In compact width, show single column.
- **Profile**: In regular width, show info panel and posts timeline side-by-side (`HStack` or `NavigationSplitView`). In compact width, stack vertically.
- **Lists**: In regular width, show a list of moderation lists with a selected detail panel (two-column). In compact width, show a single-column list with navigation push.
- **Conversation List**: In regular width, show conversation sidebar + message view side-by-side. In compact width, use navigation push to detail.
- **Timeline posts**: In regular width on iPad, use slightly wider post cells with `PostRowView` style `.full` and more generous padding.

#### Scenario: Dashboard responsive grid
- **GIVEN** an iPad in landscape (regular width)
- **WHEN** viewing Dashboard
- **THEN** cards are displayed in a 3+ column grid
- **THEN** no `iPadDashboardView` is used

#### Scenario: Profile responsive layout
- **GIVEN** an iPad in landscape (regular width)
- **WHEN** viewing a profile
- **THEN** the profile info and posts timeline appear side-by-side

#### Scenario: No iPad* wrapper files remain
- **WHEN** the refactor is complete
- **THEN** `iPadDashboardView.swift`, `iPadListsView.swift`, `iPadListDetailView.swift`, `iPadProfileInspector.swift`, `iPadTimelineView.swift`, `iPadNotificationsView.swift`, `iPadChatView.swift`, `iPadMentionsSearchWrapper.swift`, `iPadEmptyDetailPlaceholder.swift` SHALL NOT exist
