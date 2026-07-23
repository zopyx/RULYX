# Proposal: Account Switch State Reset

## Why

A code review of the account-switching path (`AccountStore.switchAccount(to:using:)`) shows that cache clearing is only partially implemented. While disk caches (URL cache, `BlueskyAPICache`, `DashboardCache`, `RelationshipCache`) and some iPhone views reset correctly, several in-memory states and UI counters survive an account switch or are never refetched:

| # | Finding | Severity |
|---|---------|----------|
| 1 | `ListsViewModel.reset()` does not clear `followingCount` / `followersCount` — dashboard shows the previous account's counters after a switch | Bug |
| 2 | `NotificationTab.onChange` calls `viewModel.reset()` but never refetches — the notification list stays empty (skeleton) until manual pull-to-refresh | Bug |
| 3 | `DirectRepliesView` / `MentionsSearchView` / `CustomSearchView` only reload target lists on account change; already-loaded results from the previous account stay on screen | Gap |
| 4 | iPad views (`iPadListsView`, `iPadDashboardView`, `iPadProfileInspector`, `iPadListDetailView`) use plain `.task {}` with no account-change handling; on iPad the iPhone views' `onChange` handlers are not in the view hierarchy, so nothing resets | Gap (major on iPad) |
| 5 | `ThreadCacheService` is only invalidated via timeline view models' `prepareForAccountChange()`; if the timeline was never created, stale thread viewer state survives | Minor |
| 6 | `HTTPRequestDebugStore` request log (contains previous account's DIDs/handles in URLs) and performance cache metrics persist across switches | Minor / decision |
| 7 | `MediaBrowserView`, `UserPostsView`, `FollowerDiffView` use plain `.task` without account-change handling; viewer-relative state persists | Minor |
| 8 | `DashboardCache.clearAll()` and `RelationshipCache.clearAll()` delete the same directory (`~/Library/Caches/com.ajung.RULYX`) — redundant double call, coarse nuke | Cleanup |

## What

Define and enforce a single rule: **when the active account changes, every account-scoped cache is cleared, every account-scoped counter in the UI is reset, and all visible account-scoped data is refetched automatically.**

- Centralize the reset contract in one place (extend `AccountStore.switchAccount` plus a dedicated `AccountSwitchCoordinator`/notification) instead of scattering resets across views.
- Fix the concrete bugs (#1, #2) and close the iPad gap (#4).
- Decide explicitly which stores are global-by-design (`MutedWordsStore`, `InternalListStore`, `AnalyticsStore`, `FeedStore` — per-DID keys) and document them as excluded.

## Non-goals

- No redesign of the cache layers themselves (TTL, LRU, keying stays as-is).
- No change to the preferred-search-account semantics.
- No UI redesign of the switcher.

## Impact

- `AccountStore.switchAccount` becomes the single orchestration point.
- Views either subscribe to a reset signal or receive reset via injected stores.
- New spec `account-switch-state-reset` becomes the source of truth for switch behavior.
