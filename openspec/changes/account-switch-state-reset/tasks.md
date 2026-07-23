# Tasks: Account Switch State Reset

## 1. Core reset sequence
- [x] 1.1 Add `ThreadCacheService.shared.invalidateAll()` to the switch path (`AccountStore.switchAccount`)
- [x] 1.2 Separate cache directories: `DashboardCache` → `com.ajung.RULYX/dashboard`, `RelationshipCache` → `com.ajung.RULYX/relationships` (no more shared-directory nuke)
- [x] 1.3 Ordering invariant documented in `switchAccount` doc comment (resets complete before `activeAccountID` assignment)
- [x] 1.4 `.accountWillSwitch` notification posted synchronously in `switchAccount` before the ID assignment; `ListsViewModel` + `NotificationViewModel` subscribe in `init` and reset counters immediately (visible reset even for non-visible tabs, before any refetch starts)

## 2. Counter fixes
- [x] 2.1 `ListsViewModel.reset()`: clears `followingCount` and `followersCount` (ListsViewModel.swift)
- [x] 2.2 `ListsViewModel.load(for: nil)` early-exit: clears `followingCount`/`followersCount` too
- [x] 2.3 Badge regression covered: notification badge reset + refetch via NotificationTab `.task(id:)`; chat badge via existing `rebuildConversations` path; new tests in ListsViewModelTests/AccountStoreTests

## 3. Automatic refetch after switch (iPhone)
- [x] 3.1 `NotificationTab`: `.task(id: activeAccount?.did)` refetches notifications + unread count + target lists; `onChange` resets (NotificationTab.swift)
- [x] 3.2 `DirectRepliesView`: onChange resets view model, re-resolves search account, reloads (DirectRepliesView.swift)
- [x] 3.3 `MentionsSearchView` / `CustomSearchView`: onChange resets view model + search account; Mentions reloads automatically
- [x] 3.4 `MediaBrowserView`, `UserPostsView`, `FollowerDiffView`: `.task(id: accountStore.activeAccountID)`

## 4. iPad parity
- [x] 4.1 `iPadListsView`: `.task(id:)` + onChange resets `ListsViewModel` and clears `navState.selectedList`
- [x] 4.2 `iPadDashboardView`: verified — no account-scoped fetched state (account count + global operation log only); no change needed
- [x] 4.3 `iPadProfileInspector`: `.task(id:)` + onChange `profileVM.reset()` (new `BlueskyProfileViewModel.reset()`)
- [x] 4.4 `iPadListDetailView`: id-keyed tasks (list + account) for members and subscription state; removed force-unwrap of `activeAccount`

## 5. Documentation & decisions
- [x] 5.1 Global-by-design stores documented (MutedWords, InternalList, Analytics, FeedStore, WorkspacePreferences, thumbnails) — AGENTS.md "Account Switch — State Reset Contract"
- [x] 5.2 Decision documented: `HTTPRequestDebugStore` log + cache metrics survive switches (debug feature) — AGENTS.md
- [x] 5.3 AGENTS.md updated with the reset contract (orchestration point, ordering invariant, layer table, rules for new stores)

## 6. Verification
- [x] 6.1 Unit tests: `ListsViewModel.reset()` / `load(for: nil)` clear all four counters (ListsViewModelTests)
- [x] 6.2 Unit tests: `switchAccount` invalidates `ThreadCacheService`, tracks previous ID, no-op on same account (AccountStoreTests)
- [ ] 6.3 Manual: switch with Notifications visible (iPhone) → auto-reload, no stale rows
- [ ] 6.4 Manual: switch on iPad dashboard → all counters/lists reset and reload
- [ ] 6.5 `swiftformat --lint .` + `swiftlint` clean; build + test suite succeeds
