## ADDED Requirements

### Requirement: List members SHALL be loaded in paginated pages
The list detail view SHALL load members in pages (default: 50 per page) instead of fetching all members at once. The first page SHALL appear immediately; subsequent pages SHALL load on-demand as the user scrolls.

#### Scenario: Opening a list with 1000 members
- **WHEN** the user opens a list with 1000 members
- **THEN** only the first 50 members SHALL be fetched and rendered; a loading indicator SHALL appear at the bottom
- **THEN** scrolling to the bottom SHALL trigger the next page fetch automatically

#### Scenario: All pages loaded
- **WHEN** the user has scrolled through all pages
- **THEN** no further loading indicator SHALL appear

### Requirement: Pagination state SHALL be observable
The view model SHALL expose a loading state per page so the UI can show granular progress.

#### Scenario: Page loading states
- **WHEN** page N is being fetched
- **THEN** the footer for page N SHALL show a progress indicator
- **WHEN** page N fetch fails
- **THEN** the footer SHALL show a retry button with the error message

### Requirement: Search within loaded members SHALL work client-side
The existing search/filter bar in the list detail view SHALL filter against the currently loaded (paginated) members without triggering additional API calls.

#### Scenario: Client-side search
- **WHEN** the user types in the search bar
- **THEN** the displayed members SHALL be filtered from the in-memory loaded set
- **WHEN** no loaded member matches the search
- **THEN** a "no matches" empty state SHALL be shown
