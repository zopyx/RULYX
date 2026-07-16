## ADDED Requirements

### Requirement: TimelineComposeFAB is a reusable floating action button
A shared `TimelineComposeFAB` component SHALL render the "New Post" floating action button consistently across all timeline views.

The component SHALL:
- Display a `square.and.pencil` SF Symbol in a filled circle using `Color.skyPrimary`
- Accept a binding or action for tap handling
- Support an `isVisible` parameter that animates appearance/disappearance with `.scale.combined(with: .opacity)`
- Apply the accessibility label `timeline.new_post`
- Position itself via `.overlay(alignment: .bottomTrailing)` with standard padding (16pt trailing, 16pt bottom)

#### Scenario: FeedTimelineView uses shared FAB
- **WHEN** `FeedTimelineView` renders the new-post button
- **THEN** it SHALL use `TimelineComposeFAB` instead of an inline `Button` implementation

#### Scenario: ListTimelineView uses shared FAB
- **WHEN** `ListTimelineView` renders the new-post button
- **THEN** it SHALL use `TimelineComposeFAB` instead of the `composeFAB` private computed property

#### Scenario: FAB visibility respects view state
- **WHEN** a timeline view sets `isVisible = false`
- **THEN** the FAB SHALL animate out and not be tappable

### Requirement: TimelineSheets consolidates all timeline-related sheet presentations
A shared view modifier or component `TimelineSheets` SHALL consolidate all sheet presentations common to timeline views: compose, reply, quote, image/video preview, likes list, profile sheet, share sheet, edit post, and delete confirmation.

Each sheet SHALL accept the same parameters regardless of which timeline view uses it.

#### Scenario: FeedTimelineView uses shared sheets
- **WHEN** `FeedTimelineView` presents any of the following sheets: image preview, video player, likes list, feed picker, new post composer, reply composer, quote composer, edit post, profile, share, delete confirmation
- **THEN** it SHALL use `TimelineSheets` or its constituent modifiers instead of inline `.sheet()`/`.fullScreenCover()` modifiers

#### Scenario: ListTimelineView uses shared sheets
- **WHEN** `ListTimelineView` presents any sheet
- **THEN** it SHALL use the same shared sheet components as `FeedTimelineView`

### Requirement: TimelinePostRow is a self-contained post row component
A shared `TimelinePostRow` component SHALL encapsulate: the `PostRowView` with callbacks, context menu, swipe actions (like left, reply right), inline thread expansion section, and AI classification badge.

The component SHALL accept:
- `entry: RichFeedEntry`
- View model reference (via protocol) for optimistic state queries
- Callback closures for navigation actions (tap thread, open profile, etc.)

#### Scenario: Both timelines use shared post row
- **WHEN** `FeedTimelineView` and `ListTimelineView` render individual post rows
- **THEN** both SHALL use `TimelinePostRow` instead of their respective private `postRowView` methods

#### Scenario: Context menu is consistent
- **WHEN** a user long-presses a post in any timeline
- **THEN** the context menu SHALL contain the same actions (Copy, Share, Mute User, Block User, Report, Translate, Mute Word) in the same order

#### Scenario: Swipe actions are consistent
- **WHEN** a user swipes a post in any timeline
- **THEN** left swipe SHALL toggle like; right swipe SHALL trigger reply
