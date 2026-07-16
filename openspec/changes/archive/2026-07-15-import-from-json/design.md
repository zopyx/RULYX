## Context

The `RelationshipsView` (`Sources/Features/Lists/RelationshipsView.swift`, 936 lines) already provides:

- Four relationship modes: followers, following, blocking, blockedBy
- Export to CSV, JSON, XLSX, ODS via `ExportFormat` enum
- JSON export format: `[{"handle": "...", "did": "...", "display_name": "...", "created_at": "...", "description": "...", "followers": N, "following": N, "posts": N}]`
- `LiveBlueskyClient.followActor(did:account:appPassword:)` for following
- `LiveBlueskyClient.resolveHandle(_:)` (check existence)
- `BatchOperationProgressView` for batch operation progress UI (blocking, add-to-list)
- `BatchOperationConfig` model with `PendingLikerTarget`

The import feature reuses all of these — no new services, models, or dependencies.

## Goals / Non-Goals

**Goals:**
- Allow the user to select a `.json` file via `fileImporter` from the export menu
- Parse the same JSON array format that the export produces
- Follow each account in the file using the active account
- Show real-time progress with success/failure/skipped counts
- Rate-limit API calls to avoid hitting Bluesky rate limits

**Non-Goals:**
- Import from CSV/XLSX/ODS (not implementing format conversion — only JSON, matching the export)
- Import to moderation/internal/curation lists (only follow operations)
- Edit/validate the JSON before import
- Background import when app is in background

## Decisions

### Decision 1: Add import to existing export menu rather than a separate button
**Rationale:** The export menu in the toolbar already groups file-based data operations. Adding "Import from JSON" as the first item keeps the UI surface minimal. The existing `isExporting` / `shareFileURL` pattern is extended rather than introducing a new toolbar item.

**Alternative considered:** Dedicated "Import" toolbar button. Rejected because it adds clutter for a rarely-used operation.

### Decision 2: Reuse `BatchOperationProgressView` pattern rather than inline progress
**Rationale:** The existing `BatchOperationConfig` → `BatchOperationProgressView` flow in `RelationshipsView` already handles: target processing with progress, success/failure/skipped counts, and dismissable sheet. The import follows the same shape (list of targets → process each one → show progress). Reusing the pattern avoids reinventing the progress UI.

**Alternative considered:** Inline progress bar with `.task`. Rejected because it doesn't give the user dismiss or summary feedback.

### Decision 3: Rate-limit at 1 follow/second rather than batching
**Rationale:** Bluesky's `com.atproto.repo.createRecord` endpoint is subject to per-account rate limits. Sending all follows concurrently would trigger 429 errors. A simple 1-second delay between calls is conservative and predictable.

**Alternative considered:** Concurrent with exponential backoff. More complex and harder to predict for the user.

### Decision 4: Handle resolution before follow (handle → DID)
**Rationale:** The exported JSON may contain only `handle` (e.g., from Bluesky's native data export which doesn't include DID). The `followActor` API requires a DID, so handles must be resolved first. Using `resolveHandle` from `LiveBlueskyClient` (which is the same client already used throughout the app) keeps it consistent.

### Decision 5: Deduplication via `fetchFollowing` check
**Rationale:** To avoid "already following" API errors, the importer fetches the user's existing following list (paginated) before processing and skips DIDs already followed. This avoids unnecessary API calls and error handling.

**Alternative considered:** Try-follow and catch. Simpler but generates API errors that need parsing. Pre-check is cleaner.

## Implementation Plan

1. Add `ImportFollowConfig` struct (analogous to `BatchOperationConfig`) with `targets: [PendingLikerTarget]`
2. Add `@State private var importConfig: ImportFollowConfig?` to `RelationshipsView`
3. Add `importFromJSON()` method that:
   a. Opens `fileImporter` with `.json` UTType
   b. Reads and decodes the JSON
   c. Builds `[PendingLikerTarget]` from the parsed entries
   d. Presents `ImportFollowProgressView` sheet
4. Create `ImportFollowProgressView` that:
   a. Fetches the user's following list for dedup
   b. Resolves handles to DIDs as needed
   c. Calls `followActor` with 1s delay between calls
   d. Shows progress with counts
5. Add "Import from JSON" menu item to the export menu (above the export options)
6. Add localization keys: `rel.import_json`, `rel.import_json.progress`, `rel.import_json.parse_error`, `rel.import_json.success`, `rel.import_json.already_following`

## Risks / Trade-offs

| Risk | Mitigation |
|------|-----------|
| Rate limit (429) during bulk follow | 1s delay between calls; show "rate limited" in failure count |
| Very large JSON file (1000+ accounts) | Progress sheet shows real-time progress; user can dismiss to cancel (sheet dismiss cancels the task) |
| Handle resolution adds latency | Resolve DIDs first, then follow; progress shows counts for each phase |
| JSON format drift (future export changes) | Importer only requires `did` or `handle`; all other fields are ignored — forward-compatible |
