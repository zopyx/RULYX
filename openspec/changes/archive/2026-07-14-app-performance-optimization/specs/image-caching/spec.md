## ADDED Requirements

### Requirement: Avatar and thumbnail images SHALL be cached in memory
The system SHALL maintain an in-memory LRU cache for all avatar and thumbnail images to avoid redundant network fetches during the same app session.

#### Scenario: Repeated avatar display
- **WHEN** the same avatar URL appears in a second post row
- **THEN** the image SHALL be served from the in-memory cache without a network request

#### Scenario: Tab switching
- **WHEN** the user navigates away from a tab and returns to it
- **THEN** avatars in the visible rows SHALL display from cache, not initiate new network requests

### Requirement: Avatar and thumbnail images SHALL be cached on disk
The system SHALL maintain a persistent on-disk cache for all avatar and thumbnail images to survive app relaunches.

#### Scenario: Cold launch cache hit
- **WHEN** the app launches for the second time and displays the same feed
- **THEN** previously fetched avatars SHALL display from disk cache without network requests

#### Scenario: Cache eviction
- **WHEN** the disk cache exceeds 50 MB
- **THEN** the system SHALL evict the least recently used entries until usage drops below 40 MB

### Requirement: Image cache SHALL have a configurable TTL
Cached images older than the configured TTL SHALL be re-fetched from the network to prevent permanently stale avatars.

#### Scenario: TTL expiry
- **WHEN** a cached image is older than 24 hours
- **THEN** the system SHALL re-fetch the image from the network on next display

#### Scenario: Fresh image
- **WHEN** a cached image was fetched less than 24 hours ago
- **THEN** the system SHALL serve the cached version

### Requirement: The FreshAvatarImage component SHALL use ThumbnailPipeline instead of ephemeral URLSession
The `FreshAvatarImage` view SHALL delegate image loading to the existing `ThumbnailPipeline` actor (which already provides in-memory caching and ImageIO downsampling) instead of its own ephemeral `URLSession`.

#### Scenario: FreshAvatarImage loads via pipeline
- **WHEN** `FreshAvatarImage` displays an avatar URL
- **THEN** the image SHALL be fetched through `ThumbnailPipeline` and benefit from its cache

#### Scenario: ThumbnailPipeline supports disk cache
- **WHEN** `ThumbnailPipeline.image(for:maxPixelSize:scale:)` is called
- **THEN** it SHALL check the in-memory cache first, then the disk cache, then fetch from network
