## Why

The RULYX iOS app feels sluggish in several key areas: avatar images re-fetch on every view appearance, timeline scrolling stutters on complex rows, large views re-render excessively, and cold-launch image loading has no persistent cache. These issues accumulate to make the app feel unresponsive compared to native iOS experiences. Optimizing these paths will deliver a markedly snappier, more professional feel.

## What Changes

- **Avatar caching overhaul**: Replace ephemeral URLSession in `FreshAvatarImage` with the existing `ThumbnailPipeline` (NSCache-backed) and add persistent disk caching for avatars.
- **Thumbnail disk cache**: Add file-based persistent cache to `ThumbnailPipeline` so images survive app relaunches.
- **View body optimization**: Reduce unnecessary SwiftUI body re-evaluations by converting key `ObservableObject` view models to the `@Observable` macro pattern and adding `EquatableView` conformance to expensive row types.
- **Timeline polling efficiency**: Throttle polling to only active when the timeline tab is visible, and batch UI updates.
- **RelationshipsView/BlueskyProfileView decomposition**: Break large view bodies into smaller computed subviews, add `Equatable` conformance on row models to avoid needless re-renders.
- **List view lazy-loading**: Ensure large lists use proper lazy rendering with minimal identity cost.
- **HTTP client connection reuse**: Verify `URLSession` configuration for connection pooling and HTTP/2 multiplexing.

## Capabilities

### New Capabilities
- `image-caching`: Persistent on-disk + in-memory LRU cache for avatar and thumbnail images, reducing network fetches by 80%+ on re-visits.
- `view-rendering-efficiency`: Optimized SwiftUI body granularity — views only invalidate when their specific data changes, not on parent state changes.
- `timeline-polling-efficiency`: Context-aware polling that only runs when the timeline is visible, reducing background network churn by ~90%.

### Modified Capabilities
- *(none — pure performance improvements, no spec-level behavior changes)*

## Impact

- **Files modified**: `FreshAvatarImage.swift`, `ThumbnailImageView.swift`, `PostAuthorHeader.swift`, `BlueskyActorRow.swift`, `FeedTimelineViewModel.swift`, `FeedTimelineView.swift`, `RelationshipsView.swift`, `BlueskyProfileViewModel.swift`, `BlueskyProfileView.swift`, `ListsViewModel.swift`, `ListsView.swift`, `HTTPClient.swift`
- **No API changes** — all optimizations are internal to the app
- **No data model changes** — no CoreData migration, no JSON schema changes
- **No new dependencies** — uses Foundation-level caches only
- **Risk area**: Image caching changes could show stale avatars — mitigated by TTL-based eviction (24h default)
