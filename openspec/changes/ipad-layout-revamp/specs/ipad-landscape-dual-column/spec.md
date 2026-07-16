## ADDED Requirements

### Requirement: Individual tabs may use NavigationSplitView in landscape
In landscape on iPad (regular horizontal size class), individual tabs MAY present a `NavigationSplitView` within the tab content to provide a detail column for list+detail workflows. This SHALL NOT affect the top-level navigation (tab bar remains).

The moderation tab SHALL support this pattern:
- Sidebar column: list of moderation lists
- Content column: selected list members
- Detail column (optional): member profile

#### Scenario: Lists tab landscape split
- **GIVEN** an iPad in landscape
- **WHEN** the user is on the moderation tab
- **THEN** a `NavigationSplitView` is shown within the tab content
- **WHEN** the user selects a list
- **THEN** the right column shows the list members

#### Scenario: Lists tab portrait single column
- **GIVEN** an iPad in portrait (compact width)
- **WHEN** the user is on the moderation tab
- **THEN** the standard single-column list view is shown
- **THEN** selecting a list pushes the detail view onto the navigation stack
