## Why

The RelationshipsView already supports exporting followers/following as JSON. Users who export their following list (e.g., for backup or to share) have no way to re-import that data to re-follow those accounts. Adding a JSON import feature completes the round trip and gives users a way to restore or bulk-follow accounts from a file.

## What Changes

- **File import** — Add a `fileImporter` button to the existing export menu in RelationshipsView that lets the user select a JSON file
- **JSON parsing** — Parse the same JSON format that `generateJSON` produces (array of objects with `handle`, `did`, `display_name`, etc.)
- **Bulk follow** — For each entry in the file, call `LiveBlueskyClient.followActor(did:account:appPassword:)` to follow the account
- **Progress UI** — Show a progress sheet (reusing `BatchOperationProgressView` pattern) with success/failure counts and current handle
- **DID resolution** — If an entry has only a `handle` (no `did`), resolve it via the Bluesky API before following
- **Deduplication** — Skip accounts already followed by the active user

## Capabilities

### New Capabilities
- `json-follow-import`: Import a JSON file of actors and follow each one as the active account

### Modified Capabilities
- (none — no existing spec is changing)

## Impact

- **Files modified**: `RelationshipsView.swift` (add import UI + logic)
- **No new files needed** (all logic lives in the existing view or reuses existing services)
- **No new dependencies** — uses `fileImporter`, existing `followActor`, existing `BatchOperationProgressView`
- **No API changes** — pure UI addition
