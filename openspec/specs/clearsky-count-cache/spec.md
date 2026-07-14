# clearsky-count-cache Specification

## Purpose
TBD - created by archiving change dashboard-count-caching. Update Purpose after archive.
## Requirements
### Requirement: ClearSky count cached with TTL
ClearSky blocklist counts (fetchBlockingCount, fetchBlockedByCount) SHALL be cached in BlueskyAPICache with a 2-minute TTL.

#### Scenario: Dashboard loads within TTL
- **WHEN** the ListsView front page loads and cached ClearSky blocklist data is younger than 2 minutes
- **THEN** the blockingCount and blockedByCount SHALL display from cache immediately without a ClearSky API call

#### Scenario: Cache expires
- **WHEN** the ListsView front page loads and cached ClearSky data is older than 2 minutes (stale)
- **THEN** the stale count SHALL still be displayed immediately, and a background refresh SHALL update both the cache and the UI

#### Scenario: No cache exists
- **WHEN** the ListsView front page loads and no cached ClearSky data exists
- **THEN** blockingCount and blockedByCount SHALL be fetched from the ClearSky API (full pagination) and the result SHALL be cached

### Requirement: Cache invalidated on explicit refresh
Pull-to-refresh SHALL bypass the ClearSky count cache and fetch fresh data from the API.

#### Scenario: Pull-to-refresh on ListsView
- **WHEN** the user pulls to refresh on the ListsView
- **THEN** the ClearSky cache SHALL NOT be used; fresh counts SHALL be fetched from the ClearSky API

### Requirement: Cache invalidated on account switch
The ClearSky count cache SHALL be cleared when the active account changes.

#### Scenario: Account switch
- **WHEN** the user switches to a different account
- **THEN** cached counts for the previous account SHALL NOT be shown for the new account

