## 1. Define TimelineViewModel protocol

- [ ] 1.1 Create `Sources/Shared/Components/Timeline/TimelineViewModelProtocol.swift` with the protocol definition including: `entries`, `state`, `newPostCount`, `hasMore`, `isLoading`, all loading/refresh/polling methods, optimistic interaction methods, inline thread methods, lifecycle methods
- [ ] 1.2 Add default polling implementation (`startPolling`, `stopPolling`, `checkForNewPosts`, `userDidInteract`, adaptive interval logic) in a protocol extension
- [ ] 1.3 Add `@MainActor` annotation and `Sendable` conformance requirements
- [ ] 1.4 Add protocol conformance to `FeedTimelineViewModel` (minimal changes — remove duplicate polling code and rely on default implementation)
- [ ] 1.5 Verify build: `xcodebuild -project RULYX.xcodeproj -scheme RULYX -destination 'platform=iOS Simulator' build CODE_SIGNING_ALLOWED=NO`

## 2. Extract shared timeline UI components

- [ ] 2.1 Create `Sources/Shared/Components/Timeline/` directory
- [ ] 2.2 Extract `TimelineComposeFAB` — FAB with `square.and.pencil`, skyPrimary tint, scale+opacity transition, accessibility label
- [ ] 2.3 Extract `TimelinePostRow` — wraps `PostRowView` + context menu + swipe actions + inline thread section + AI badge. Accepts `entry`, `viewModel` (protocol-typed), navigation callbacks
- [ ] 2.4 Extract `TimelineSheets` — view modifier or standalone view consolidating all 8+ sheet types (image carousel, video player, likes list, feed picker, new post composer, reply composer, quote composer, edit post, profile sheet, share sheet, delete confirmation)
- [ ] 2.5 Wire `FeedTimelineView` to use `TimelineComposeFAB`, `TimelinePostRow`, and `TimelineSheets`
- [ ] 2.6 Verify build + check that `FeedTimelineView` line count is reduced to ~300 lines

## 3. Migrate ListTimelineViewModel to TimelineState

- [ ] 3.1 Replace `isLoading`/`isLoadingMore`/`hasMore`/`errorMessage` properties with `state: TimelineState`
- [ ] 3.2 Update `loadTimeline()`, `loadMore()`, `refresh()` to set `state` appropriately (`.initialLoading` → `.loaded`/`.empty`/`.failed`, `.loadingMore` → `.loaded`/`.exhausted`/`.loadMoreFailed`)
- [ ] 3.3 Add computed `var newPostCount: Int` (initially 0, will be populated by polling in task 4.x)
- [ ] 3.4 Add protocol conformance to `TimelineViewModel`
- [ ] 3.5 Verify build — no callers of deprecated properties remain

## 4. Add polling to ListTimelineViewModel

- [ ] 4.1 Add `knownURIs: Set<String>` and `newPostCount` tracking
- [ ] 4.2 Populate `knownURIs` during initial load and refresh
- [ ] 4.3 Implement `fetchFeed()` private method that routes to `fetchListFeed` (respecting `sourceMode`)
- [ ] 4.4 Verify polling starts/stops correctly with `ListTimelineView` appear/disappear lifecycle
- [ ] 4.5 Verify adaptive back-off works (manual test: wait 2+ min without interaction, confirm interval goes to 30s)

## 5. Wire ListTimelineView to shared components

- [ ] 5.1 Replace `composeFAB` with `TimelineComposeFAB`
- [ ] 5.2 Replace `postRowView(entry:)` and `postRowCallbacks(entry:)` with `TimelinePostRow`
- [ ] 5.3 Replace inline sheet modifiers with `TimelineSheets`
- [ ] 5.4 Remove internal `NavigationStack` from `ListTimelineView`
- [ ] 5.5 Audit all callers and add `NavigationStack` wrapper where needed:
  - `ListDetailView` (called from `ModerationSplitView` / `ListsView`)
  - `InternalListDetailView`
  - `iPadListDetailView`
- [ ] 5.6 Verify build + verify `ListTimelineView` line count reduced to ~250 lines

## 6. Cleanup and validation

- [ ] 6.1 Remove dead code from both view models and views
- [ ] 6.2 Verify mute-word context menu action is present in `TimelinePostRow` (currently only in FeedTimelineView)
- [ ] 6.3 Manual smoke test: main feed timeline (scroll, refresh, like, repost, reply, quote, inline threads, image preview, video, profile sheet, delete, share, mute word)
- [ ] 6.4 Manual smoke test: list timeline (open a list, scroll, like, repost, reply, inline threads, polling banner, refresh)
- [ ] 6.5 Manual smoke test: account switch (confirm both timelines reload correctly)
- [ ] 6.6 Manual smoke test: iPad (confirm both timelines render in split view detail column)
- [ ] 6.7 Run `make lint` and fix any warnings
- [ ] 6.8 Run `make test` and confirm all existing tests pass
- [ ] 6.9 Run `openspec validate timeline-consistency --json` and fix any issues
