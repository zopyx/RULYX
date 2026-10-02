# clearsky-count-cache Specification

## Purpose
Blocklist counts shown on the ListsView dashboard (blocking, blocked-by) are cached with a
TTL so the front page paints immediately. The sources are the AT Protocol itself — the
account's own repo for "blocking" and the Constellation backlink index for "blocked by" —
so there is no third-party API in this path. (Spec name kept for continuity; it predates
the removal of the ClearSky integration.)
## Requirements
### Requirement: Blocklist counts cached with TTL
Blocklist counts (fetchBlockingCount, fetchBlockedByCount) SHALL be backed by BlueskyAPICache
entries with a TTL: the own-repo walk under `repo/blocklist/{did}` and the backlink walk
under `constellation/blocked-by/{did}`.

#### Scenario: Dashboard loads within TTL
- **WHEN** the ListsView front page loads and the cached blocklist data is younger than the TTL
- **THEN** the blockingCount and blockedByCount SHALL display from cache immediately without a source request

#### Scenario: Cache expires
- **WHEN** the ListsView front page loads and the cached data is older than the TTL (stale)
- **THEN** the stale count SHALL still be displayed immediately, and a background refresh SHALL update both the cache and the UI

#### Scenario: No cache exists
- **WHEN** the ListsView front page loads and no cached blocklist data exists
- **THEN** blockingCount SHALL be read from the account's own repo (full cursor walk) and blockedByCount from the index total, and both results SHALL be cached

### Requirement: Cache invalidated on explicit refresh
Pull-to-refresh SHALL bypass the blocklist count caches and fetch fresh data from the sources.

#### Scenario: Pull-to-refresh on ListsView
- **WHEN** the user pulls to refresh on the ListsView
- **THEN** the cached entries SHALL NOT be used; fresh counts SHALL be fetched (own repo walk / index total)

### Requirement: Cache invalidated on account switch
The blocklist count cache SHALL be cleared when the active account changes.

#### Scenario: Account switch
- **WHEN** the user switches to a different account
- **THEN** cached counts for the previous account SHALL NOT be shown for the new account
