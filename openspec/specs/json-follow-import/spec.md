# json-follow-import Specification

## Purpose
TBD - created by archiving change import-from-json. Update Purpose after archive.
## Requirements
### Requirement: User SHALL select a JSON file via fileImporter
The system SHALL provide a "Import from JSON" menu option in the RelationshipsView export menu (visible for all relationship modes) that opens a native document picker (`fileImporter`) configured to accept `.json` files.

#### Scenario: Tap import button opens file picker
- **WHEN** the user taps "Import from JSON" in the relationships export menu
- **THEN** a native iOS document picker SHALL open filtered to `.json` files

#### Scenario: Cancel file picker
- **WHEN** the user cancels the document picker
- **THEN** no action SHALL be taken and the view state SHALL remain unchanged

### Requirement: The system SHALL parse the same JSON format as the export
The importer SHALL parse JSON files matching the format produced by `generateJSON()`: an array of objects with at least one of `did` or `handle` keys. Other fields (`display_name`, `created_at`, `description`, `followers`, `following`, `posts`) SHALL be ignored. Files that are not valid JSON or do not match the expected array format SHALL display an error.

#### Scenario: Valid JSON import
- **WHEN** the user selects a JSON file containing `[{"did": "did:plc:abc", "handle": "user.bsky.social"}]`
- **THEN** the system SHALL parse the file and begin following the accounts

#### Scenario: Invalid JSON file
- **WHEN** the user selects a file that is not valid JSON
- **THEN** the system SHALL show an error message and not attempt any follows

#### Scenario: Empty array
- **WHEN** the selected JSON file contains an empty array `[]`
- **THEN** the system SHALL show an info message that no accounts were imported

#### Scenario: Missing both did and handle
- **WHEN** a JSON object has neither a `did` nor a `handle` field
- **THEN** that entry SHALL be skipped and counted in the failure count with a descriptive error

### Requirement: The system SHALL follow each account via the active account
For each entry with a valid `did` (or resolvable `handle`), the system SHALL call `LiveBlueskyClient.followActor(did:account:appPassword:)` using the active account. The system SHALL rate-limit API calls to avoid hitting Bluesky rate limits (max 1 follow per second).

#### Scenario: Successful follow
- **WHEN** a valid `did` is processed
- **THEN** `followActor` SHALL be called with that DID and the active account
- **THEN** the success count SHALL increment

#### Scenario: Already following
- **WHEN** the active account already follows the target DID
- **THEN** the system SHALL skip the follow and count it as already-followed (not as a failure)

#### Scenario: API error during follow
- **WHEN** `followActor` throws an error for a given DID
- **THEN** the failure count SHALL increment and the error SHALL be recorded
- **THEN** the system SHALL continue processing remaining entries (no abort)

### Requirement: The system SHALL resolve handles to DIDs before following
If a JSON entry has a `handle` but no `did`, the system SHALL resolve the handle to a DID using `LiveBlueskyClient.resolveHandle()`. If resolution fails, the entry SHALL be counted as a failure with a descriptive error.

#### Scenario: Handle resolution succeeds
- **WHEN** an entry has `"handle": "user.bsky.social"` and no `did`
- **THEN** the system SHALL call `resolveHandle` to obtain the DID
- **THEN** the system SHALL follow the resolved DID

#### Scenario: Handle resolution fails
- **WHEN** `resolveHandle` fails (e.g., handle does not exist)
- **THEN** the entry SHALL be counted as a failure with the error message

### Requirement: The system SHALL show a progress sheet during import
The import SHALL display a progress sheet with: total entries to process, completed count, success count, failure count, already-followed count, and the current handle being processed. The sheet SHALL remain visible until all entries are processed or the user dismisses it.

#### Scenario: Progress display
- **WHEN** import starts
- **THEN** a progress sheet SHALL be presented showing live counts

#### Scenario: Import completes
- **WHEN** all entries have been processed
- **THEN** the progress sheet SHALL show final counts (success/failure/skipped)
- **THEN** the user SHALL be able to dismiss the sheet

#### Scenario: Import error
- **WHEN** the initial JSON parsing fails
- **THEN** an error alert SHALL be shown instead of the progress sheet

