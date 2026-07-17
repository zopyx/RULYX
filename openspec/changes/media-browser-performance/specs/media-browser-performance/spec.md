## ADDED Requirements

### Requirement: Image/video counts SHALL update incrementally
The system SHALL maintain `imageCount` and `videoCount` by incrementing them as items are appended, rather than scanning the entire `items` array on every update.

#### Scenario: Appending a page with mixed media
- **GIVEN** 1000 items already loaded (600 images, 400 videos)
- **WHEN** a new page of 50 items (30 images, 20 videos) is appended
- **THEN** `imageCount` SHALL become 630 and `videoCount` 420
- **AND** no full scan of the 1050 items SHALL occur

#### Scenario: Replacing all items (new search/refresh)
- **WHEN** `replaceItems` is called with a new array
- **THEN** `imageCount` and `videoCount` SHALL be recomputed from the new array only (single pass)

### Requirement: availableFilters SHALL be cached
The `availableFilters` property SHALL be a stored `@Published` property updated only when the first image or first video appears, not a computed property scanned on every body evaluation.

#### Scenario: First video appears
- **GIVEN** only images have been loaded so far (`availableFilters == [.images]`)
- **WHEN** a page containing a video is appended
- **THEN** `availableFilters` SHALL become `[.images, .videos]`
- **AND** subsequent body evaluations SHALL NOT re-scan `items`

### Requirement: filteredItems SHALL only rebuild on items or filter change
The `filteredItems` array SHALL be recomputed only when `items` changes or `filter` changes. It SHALL NOT be recomputed on unrelated state changes.

#### Scenario: Filter unchanged, items unchanged
- **WHEN** `selectedIDs` is modified (select/deselect an item)
- **THEN** `filteredItems` SHALL NOT be recomputed

#### Scenario: Filter toggled from images to videos
- **WHEN** `filter` changes from `.images` to `.videos`
- **THEN** `filteredItems` SHALL be recomputed to contain only video items
