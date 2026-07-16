## 1. Foundation — Add resolveHandle public method

- [ ] 1.1 Add `func resolveHandle(_ handle: String) async throws -> String` to `LiveBlueskyClient` that calls the private `resolveHandleToDID`, making handle resolution available outside the class

## 2. Import Model & Data Types

- [ ] 2.1 Define `ImportFollowConfig` struct (Identifiable) with `targets: [PendingLikerTarget]` and active account/password — analogous to `BatchOperationConfig`
- [ ] 2.2 Define `ImportFollowEntry` Codable struct matching the JSON export format (handle, did, display_name, created_at, etc.) with only handle/did as required
- [ ] 2.3 Add `@State private var importConfig: ImportFollowConfig?` to `RelationshipsView`

## 3. Import Logic

- [ ] 3.1 Implement `importFromJSON(url: URL)` method that reads the file, decodes JSON into `[ImportFollowEntry]`, maps to `[PendingLikerTarget]`, and presents the progress sheet
- [ ] 3.2 Implement `ImportFollowProgressView` with:
  - Phase 1: Fetch the user's existing following list for deduplication
  - Phase 2: Resolve handles to DIDs (for entries missing `did`)
  - Phase 3: Call `followActor` for each target with 1s delay
  - Live counts: total, completed, success, already-followed, failed
  - Current handle display
  - Dismiss button (cancels the task)
- [ ] 3.3 Wire the `fileImporter` modifier to `RelationshipsView` body, triggered by the import menu item

## 4. UI — Add Import Menu Item

- [ ] 4.1 Add "Import from JSON" menu item to the export `Menu` in `RelationshipsView` toolbar (above the export options, separated by `Divider`)
- [ ] 4.2 Conditionally show the sheet with `ImportFollowProgressView` when `importConfig` is set
- [ ] 4.3 Handle JSON parse errors with an alert

## 5. Localization

- [ ] 5.1 Add localization keys to `en.json`:
  - `"rel.import_json": "Import from JSON"`
  - `"rel.import_json.progress": "Importing followers..."`
  - `"rel.import_json.completed": "{success} followed, {skipped} already following, {failed} failed"`
  - `"rel.import_json.parse_error": "Could not read the file. Expected a JSON array of actor objects."`
  - `"rel.import_json.empty": "The file contains no importable entries."`
  - `"rel.import_json.title": "Import Follows"`

## 6. Verify & Polish

- [ ] 6.1 Run `swiftformat --lint .` and fix any formatting issues
- [ ] 6.2 Verify the feature compiles with `xcodebuild` for iOS Simulator
