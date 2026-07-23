# Design: Account Switch State Reset

## Current architecture (reviewed)

`AccountStore.switchAccount(to:using:)` (Sources/Domain/Services/AccountStore.swift:297) currently:
1. Sets `previousActiveAccountID`
2. `await client.clearAllCaches()` — URL session cache, `URLCache.shared`, session cache, `BlueskyAPICache` disk cache
3. `DashboardCache.clearAll()` + `RelationshipCache.clearAll()` — both delete the same directory
4. Sets `activeAccountID` → `@Published` fires

Downstream reactions today:
- `RULYXApp` `.onReceive(accountStore.$activeAccountID.dropFirst())` → `chatStore.rebuildConversations(clearCaches: true)` (chat reset works)
- iPhone views: `ListsView`, `TimelineTab`, `FeedTimelineView`, `NotificationTab`, `ConversationListView` use `.onChange(of: accountStore.activeAccount…)` / `.task(id:)` — partially working, gaps per proposal
- iPad views (`Sources/App/iPad/*`): no account-change handling at all
- `ThreadCacheService.shared`: only invalidated inside timeline view models' `prepareForAccountChange()`

## Approach

Keep `switchAccount` as the single entry point and add a deterministic, ordered reset sequence:

```
switchAccount(to:using:)
  1. guard no-op checks
  2. previousActiveAccountID = activeAccountID
  3. await resetAllAccountScopedState(client)   // NEW — one ordered sequence
  4. activeAccountID = account.id               // fires UI reactions LAST
  5. persist()
```

### Step 3: `resetAllAccountScopedState`

Ordered before `activeAccountID` changes so no view can refetch into a half-cleared state:

- `await client.clearAllCaches()` (unchanged)
- `DashboardCache.clearAll()` — keep one call; remove the redundant `RelationshipCache.clearAll()` **or** give each cache its own subdirectory (preferred: separate subdirectories `com.ajung.RULYX/dashboard` and `com.ajung.RULYX/relationships` so `clearAll()` stops nuking sibling files; note both currently share `~/Library/Caches/com.ajung.RULYX`)
- `await ThreadCacheService.shared.invalidateAll()` — move here from the timeline view models (they keep their own call harmlessly, or drop it)
- Post `Notification.Name.accountWillSwitch` **synchronously** on the main actor (object = new `AppAccount`), so view models the `AccountStore` cannot reach directly (DI boundary — `ListsViewModel` is view-owned via `@State` in three views) zero their counters in the same runloop turn, before any view re-renders or refetches. Implemented: `ListsViewModel` + `NotificationViewModel` subscribe in `init`, reset via `MainActor.assumeIsolated`, unregister in `deinit` (observer token stored `nonisolated(unsafe)` — Swift 6 deinit is nonisolated). No-op switches post nothing.

### Per-view/per-store fixes

| Area | Fix |
|------|-----|
| `ListsViewModel.reset()` (ListsViewModel.swift:37) | Also nil `followingCount` and `followersCount`; same for the `load(for: nil)` early-exit path |
| `NotificationTab` (NotificationTab.swift:92) | `.onChange(of: accountStore.activeAccount?.did)`: after `viewModel.reset()`, trigger `Task { await viewModel.load(...) ; await viewModel.updateUnreadCount(...) ; await loadTargetLists(...) }` for the new account — or convert `.task` to `.task(id: accountStore.activeAccount?.did)` and keep reset in onChange |
| Search views (`DirectRepliesView`, `MentionsSearchView`, `CustomSearchView`) | On active-account change: clear loaded results (entries/replies + cursors) and re-run the auto-load path where one exists; reload target lists as today |
| iPad views (`iPadListsView`, `iPadDashboardView`, `iPadProfileInspector`, `iPadListDetailView`) | Change `.task {}` → `.task(id: accountStore.activeAccountID)` and call `viewModel.reset()` (where a shared view model exists) before reloading; alternatively subscribe to the new `accountDidSwitch` notification |
| `MediaBrowserView`, `UserPostsView`, `FollowerDiffView` | `.task(id: accountStore.activeAccountID)` so a switch reloads with the new account's viewer context |
| `HTTPRequestDebugStore` + perf metrics | Explicit decision: keep logs across switches (debug feature), document in spec; optionally add `resetMetrics()` call on `BlueskyAPICache.shared` |

### Global-by-design (excluded, documented)

- `MutedWordsStore` — user preference, account-independent
- `InternalListStore` — app-local lists, intentionally shared across accounts
- `AnalyticsStore` — engagement snapshots keyed by post URI (post-global, not viewer-relative)
- `FeedStore` — already per-DID keys
- `WorkspacePreferencesStore` — saved/recent searches, user-level
- `ThumbnailPipeline`/media thumbnail `URLCache` — public CDN content, not viewer-relative

## Risks

- Double reload on iPhone where both `.task(id:)` and `.onChange` fire — mitigate by resetting in `onChange` and loading only via `.task(id:)`, or debounce.
- Ordering: `activeAccountID` must change only after resets complete, otherwise views refetch into cleared-but-not-yet-rebuilt stores (chat already relies on this ordering).
- `switchAccount` is `async`; callers already `await` it before `returnToModerationRoot()` — keep that contract.

## Known limitations (follow-up)

- **In-flight load race in scan-style view models** (`DirectRepliesViewModel`, `MentionsSearchViewModel`): if an account switch happens while `load()` is mid-flight, the old load can still write its results after `reset()`. A generation-token pattern (as in `ChatStore`) would close this; in practice the window is small and the moderation-tab navigation reset usually destroys these views on switch.
- `ListDetailSubscribeSection` (iPadListDetailView) still force-unwraps `activeAccount` in view-building code — pre-existing; only reachable while an account is active.

## Verification

- Unit tests: `ListsViewModel.reset()` clears all four counters; `switchAccount` invokes `ThreadCacheService.invalidateAll()`.
- UI/manual: switch accounts with Notifications tab visible → list reloads automatically; repeat on iPad dashboard; confirm no previous-account data visible at any point (including during the loading window).
