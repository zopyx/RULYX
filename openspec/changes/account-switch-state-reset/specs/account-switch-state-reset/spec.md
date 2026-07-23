# account-switch-state-reset Spec (Delta)

## ADDED Requirements

### Requirement: Account switch SHALL clear all account-scoped caches
When `AccountStore.switchAccount(to:using:)` completes, ALL account-scoped caches SHALL be empty: HTTP/URL caches, `BlueskyAPICache` (disk), `DashboardCache`, `RelationshipCache`, chat service caches, and the in-memory `ThreadCacheService`.

#### Scenario: Switch clears disk caches
- GIVEN account A is active and its dashboard/timeline data is cached on disk
- WHEN the user switches to account B
- THEN `BlueskyAPICache`, `DashboardCache`, and `RelationshipCache` contain no entries
- AND `URLCache.shared` and the client's session cache are empty

#### Scenario: Switch clears thread cache unconditionally
- GIVEN `ThreadCacheService` holds thread entries viewed under account A
- WHEN the user switches to account B
- THEN `ThreadCacheService` is invalidated, even if no timeline view model was ever created

### Requirement: Account switch SHALL reset all account-scoped UI counters
After a switch, every counter derived from the previous account SHALL show its empty/initial state until fresh data arrives: dashboard blocking/blocked-by/following/followers counts, notification unread badge, chat unread badge, timeline new-post count, and optimistic like/repost counters.

#### Scenario: Dashboard counters reset
- GIVEN the dashboard shows account A's blocking/following counts
- WHEN the user switches to account B
- THEN `ListsViewModel` exposes nil for `blockingCount`, `blockedByCount`, `followingCount`, and `followersCount` before refetch

#### Scenario: Notification badge reset
- GIVEN the Notifications tab badge shows 5 unread for account A
- WHEN the user switches to account B
- THEN the badge clears immediately and refetches account B's unread count

### Requirement: Account switch SHALL automatically refetch visible account-scoped data
Every visible view showing account-scoped data SHALL reload without manual user action after a switch. This applies equally to iPhone (TabView) and iPad (NavigationSplitView) layouts.

#### Scenario: Notifications refetch after switch
- GIVEN the Notifications tab is visible
- WHEN the user switches accounts
- THEN the notification list resets AND a fresh load for the new account starts automatically (no pull-to-refresh required)

#### Scenario: iPad dashboard refetch after switch
- GIVEN the iPad dashboard/lists view is visible under account A
- WHEN the user switches to account B via the sidebar account menu
- THEN lists, profile, and counters reset and reload for account B

#### Scenario: Search results do not leak across accounts
- GIVEN `DirectRepliesView`/`MentionsSearchView`/`CustomSearchView` display results loaded under account A
- WHEN the user switches to account B
- THEN those results are cleared (and reloaded if the view auto-loads)

### Requirement: Reset behavior SHALL be centralized and deterministic
The reset SHALL be orchestrated from a single code path (the account-switch flow), not re-implemented per view. Stores/views that are global by design (`MutedWordsStore`, `InternalListStore`, `AnalyticsStore`, `FeedStore`) SHALL be documented as excluded.

#### Scenario: Single orchestration point
- WHEN a developer adds a new account-scoped store
- THEN there is exactly one documented place to register its reset behavior

#### Scenario: Debug tooling decision documented
- WHEN `HTTPRequestDebugStore` and performance cache metrics survive a switch
- THEN this is an explicit, documented decision (not an oversight)
