## ADDED Requirements

### Requirement: Media scan SHALL fetch pages in parallel
The `countMedia` method SHALL use `withTaskGroup` to fetch up to 3 pages concurrently instead of fetching them sequentially.

#### Scenario: Parallel fetch
- **WHEN** scanning a profile with 1000 posts
- **THEN** the scan SHALL fetch up to 3 pages concurrently
- **THEN** the total scan time SHALL be reduced by ~3x compared to sequential fetching

### Requirement: Media scan SHALL be capped at 1000 posts
The scan SHALL stop after processing 1000 posts (10 pages of 100) to bound execution time.

#### Scenario: Depth limit
- **WHEN** a profile has 5000+ posts
- **THEN** the scan SHALL stop after processing 1000 posts

### Requirement: Media scan results SHALL be cached
Media counts SHALL be cached per profile DID using `BlueskyAPICache`. Re-visiting a profile within the cache TTL (5 minutes) SHALL skip the scan entirely.

#### Scenario: Cached result
- **WHEN** the user opens a profile and the media scan has completed within the last 5 minutes
- **THEN** the cached counts SHALL be displayed immediately without re-scanning
