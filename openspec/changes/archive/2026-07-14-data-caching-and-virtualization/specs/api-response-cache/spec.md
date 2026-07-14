## ADDED Requirements

### Requirement: API responses SHALL be cached on disk
The system SHALL maintain a JSON-file-based on-disk cache for all Bluesky API responses, keyed by endpoint path + account DID. Cached data SHALL be returned instantly on the next request while a background refresh updates it.

#### Scenario: Re-opening a profile
- **WHEN** the user opens a profile, navigates away, and opens the same profile within 2 minutes
- **THEN** the profile data SHALL display immediately from cache, then refresh in the background

#### Scenario: Cache miss
- **WHEN** the user opens a profile that has never been viewed before
- **THEN** the data SHALL be fetched from the network as usual

#### Scenario: Stale cache on pull-to-refresh
- **WHEN** the user pulls to refresh
- **THEN** the cache SHALL be bypassed and fresh data fetched from the network

### Requirement: Cache entries SHALL have configurable TTL
Each cache entry SHALL have a time-to-live. After TTL expiry, the entry is stale and SHALL be refreshed on next read.

#### Scenario: Profile TTL expiry
- **WHEN** a cached profile is older than 120 seconds (TTL: 2 minutes)
- **THEN** the cache entry SHALL be treated as stale and re-fetched from the network while the stale data is still shown

#### Scenario: List TTL expiry
- **WHEN** a cached list member page is older than 300 seconds (TTL: 5 minutes)
- **THEN** the cache entry SHALL be treated as stale and re-fetched

### Requirement: Cache SHALL be isolated per account
Cache entries SHALL be keyed by account DID so switching accounts shows the correct cached data.

#### Scenario: Account switch
- **WHEN** the user switches from account A to account B and opens the same list
- **THEN** account B's cached members SHALL be shown, not account A's

### Requirement: Cache SHALL support automatic eviction
When the total cache size exceeds 10 MB, the oldest entries SHALL be evicted until usage drops below 8 MB.

#### Scenario: Cache eviction
- **WHEN** a new cache entry is written and total size exceeds 10 MB
- **THEN** the least recently accessed entries SHALL be deleted until total size is below 8 MB

### Requirement: Cache SHALL support manual clearing
The system SHALL provide a "Clear API Cache" button in Settings.

#### Scenario: Manual cache clear
- **WHEN** the user taps "Clear API Cache" in Settings
- **THEN** all cached API responses SHALL be deleted and the next request fetches fresh data
